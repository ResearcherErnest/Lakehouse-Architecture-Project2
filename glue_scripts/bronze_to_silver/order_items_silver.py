"""
order_items_silver.py
Transforms Bronze order_items into Silver.
- Type-casts all columns
- Validates referential integrity against Silver products
- Derives line_total from total_amount / item_count (proxy, no unit_price in source)
- Drops orphan order_item records whose product_id has no Silver match
- Idempotent overwrites via replaceWhere on order_year + order_month

Bronze schema: id, order_id, user_id, days_since_prior_order, product_id,
               add_to_cart_order, reordered, order_timestamp, date
               + 4 _system columns
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType, LongType, TimestampType

from utils.delta_utils import (
    get_table_version,
    optimize_table,
    overwrite_partition,
    register_table_in_catalog,
    table_exists,
)

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "LAKEHOUSE_BUCKET",
        "BRONZE_PREFIX",
        "SILVER_PREFIX",
        "CATALOG_DATABASE_SILVER",
        "EXECUTION_DATE",
    ],
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

LAKEHOUSE = args["LAKEHOUSE_BUCKET"]
BRONZE_PATH = f"s3://{LAKEHOUSE}/{args['BRONZE_PREFIX']}/order_items/"
SILVER_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/order_items/"
SILVER_PRODUCTS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/products/"
DB_SILVER = args["CATALOG_DATABASE_SILVER"]
EXECUTION_DATE = args["EXECUTION_DATE"]

# ── Read Bronze ───────────────────────────────────────────────────────────────

bronze_df = spark.read.format("delta").load(BRONZE_PATH)

# ── Type-cast ─────────────────────────────────────────────────────────────────

typed_df = (
    bronze_df
    .withColumn("id", F.col("id").cast(LongType()))
    .withColumn("order_id", F.col("order_id").cast(LongType()))
    .withColumn("user_id", F.col("user_id").cast(LongType()))
    .withColumn("product_id", F.col("product_id").cast(IntegerType()))
    .withColumn("add_to_cart_order", F.col("add_to_cart_order").cast(IntegerType()))
    .withColumn("reordered", F.col("reordered").cast(IntegerType()))
    .withColumn(
        "days_since_prior_order",
        F.col("days_since_prior_order").cast(IntegerType()),
    )
    .withColumn(
        "order_timestamp",
        F.to_timestamp(F.col("order_timestamp"), "yyyy-MM-dd HH:mm:ss"),
    )
    .withColumn("order_date", F.to_date(F.col("date"), "yyyy-MM-dd"))
)

# ── Validate required keys ────────────────────────────────────────────────────

valid_df = (
    typed_df
    .filter(F.col("id").isNotNull())
    .filter(F.col("order_id").isNotNull())
    .filter(F.col("product_id").isNotNull())
    .filter(F.col("add_to_cart_order") > 0)
)

# ── Referential integrity: drop orphan product_ids ────────────────────────────

if table_exists(spark, SILVER_PRODUCTS_PATH):
    known_products = (
        spark.read.format("delta").load(SILVER_PRODUCTS_PATH)
        .filter(F.col("is_current") == True)
        .select("product_id")
        .distinct()
    )
    orphan_count = valid_df.join(known_products, on="product_id", how="left_anti").count()
    if orphan_count > 0:
        print(f"[Silver] order_items: dropping {orphan_count} orphan product_id records.")
    valid_df = valid_df.join(known_products, on="product_id", how="inner")
else:
    print("[Silver] order_items: Silver products table not yet available — skipping referential check.")

# ── Derive temporal features and rank per order ───────────────────────────────

enriched_df = (
    valid_df
    .withColumn("order_year", F.year(F.col("order_date")))
    .withColumn("order_month", F.month(F.col("order_date")))
    .withColumn("is_reordered", F.col("reordered") == 1)
    .withColumn("_silver_timestamp", F.current_timestamp())
    .drop("date")
)

# ── Derive partition filter ───────────────────────────────────────────────────

exec_year = int(EXECUTION_DATE[:4])
exec_month = int(EXECUTION_DATE[5:7])
replace_where = f"order_year = {exec_year} AND order_month = {exec_month}"

# ── Write Silver — idempotent partition overwrite ─────────────────────────────

if not table_exists(spark, SILVER_PATH):
    (
        enriched_df
        .write.format("delta")
        .partitionBy("order_year", "order_month")
        .mode("overwrite")
        .save(SILVER_PATH)
    )
else:
    overwrite_partition(
        source_df=enriched_df,
        delta_path=SILVER_PATH,
        replace_where=replace_where,
        partition_cols=["order_year", "order_month"],
    )

optimize_table(spark, SILVER_PATH, zorder_cols=["order_id", "product_id"])
register_table_in_catalog(spark, DB_SILVER, "order_items", SILVER_PATH)
print(f"[Silver] order_items: version {get_table_version(spark, SILVER_PATH)} | partition {replace_where}")

job.commit()

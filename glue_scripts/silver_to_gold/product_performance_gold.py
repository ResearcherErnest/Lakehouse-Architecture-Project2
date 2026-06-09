"""
product_performance_gold.py
Aggregates Silver order_items + products into a monthly product performance table.
Computes units_sold, revenue_contribution, and dept_revenue_rank per product per month.
Idempotent: replaceWhere on order_year + order_month.
OPTIMIZE + ZORDER BY order_month for Athena cost efficiency.

Gold schema:
  product_id INT, product_name STRING, department STRING,
  order_year INT, order_month INT,
  units_sold BIGINT, order_count BIGINT,
  dept_revenue_rank INT,
  reorder_rate DOUBLE,
  _gold_timestamp TIMESTAMP
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

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
        "SILVER_PREFIX",
        "GOLD_PREFIX",
        "CATALOG_DATABASE_GOLD",
        "EXECUTION_DATE",
    ],
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

LAKEHOUSE = args["LAKEHOUSE_BUCKET"]
SILVER_ITEMS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/order_items/"
SILVER_PRODUCTS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/products/"
GOLD_PATH = f"s3://{LAKEHOUSE}/{args['GOLD_PREFIX']}/product_performance/"
DB_GOLD = args["CATALOG_DATABASE_GOLD"]
EXECUTION_DATE = args["EXECUTION_DATE"]

exec_year = int(EXECUTION_DATE[:4])
exec_month = int(EXECUTION_DATE[5:7])

# ── Read Silver ───────────────────────────────────────────────────────────────

items_df = spark.read.format("delta").load(SILVER_ITEMS_PATH).filter(
    (F.col("order_year") == exec_year) & (F.col("order_month") == exec_month)
)

products_df = (
    spark.read.format("delta").load(SILVER_PRODUCTS_PATH)
    .filter(F.col("is_current") == True)
    .select("product_id", "product_name", "department")
)

# ── Join items → products ─────────────────────────────────────────────────────

items_enriched = items_df.join(products_df, on="product_id", how="left").fillna(
    {"department": "UNKNOWN", "product_name": "UNKNOWN"}
)

# ── Aggregate per product per month ──────────────────────────────────────────

product_agg = (
    items_enriched
    .groupBy("product_id", "product_name", "department", "order_year", "order_month")
    .agg(
        F.count("id").alias("units_sold"),
        F.countDistinct("order_id").alias("order_count"),
        F.sum(F.col("reordered").cast("int")).alias("reorder_count"),
    )
    .withColumn(
        "reorder_rate",
        F.round(F.col("reorder_count") / F.col("units_sold"), 4),
    )
)

# ── Rank products within each department by units_sold ────────────────────────

dept_window = Window.partitionBy("department", "order_year", "order_month").orderBy(
    F.col("units_sold").desc()
)

gold_df = (
    product_agg
    .withColumn("dept_revenue_rank", F.rank().over(dept_window))
    .drop("reorder_count")
    .withColumn("_gold_timestamp", F.current_timestamp())
)

# ── Write Gold — idempotent partition overwrite ───────────────────────────────

replace_where = f"order_year = {exec_year} AND order_month = {exec_month}"

if not table_exists(spark, GOLD_PATH):
    (
        gold_df
        .write.format("delta")
        .partitionBy("order_year", "order_month")
        .mode("overwrite")
        .save(GOLD_PATH)
    )
else:
    overwrite_partition(
        source_df=gold_df,
        delta_path=GOLD_PATH,
        replace_where=replace_where,
        partition_cols=["order_year", "order_month"],
    )

optimize_table(spark, GOLD_PATH, zorder_cols=["order_month", "department", "dept_revenue_rank"])
register_table_in_catalog(spark, DB_GOLD, "product_performance", GOLD_PATH)
print(f"[Gold] product_performance: version {get_table_version(spark, GOLD_PATH)} | {exec_year}-{exec_month:02d}")

job.commit()

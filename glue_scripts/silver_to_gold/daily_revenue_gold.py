"""
daily_revenue_gold.py
Aggregates Silver orders + order_items into a Gold daily revenue table.
Groups by order_date and department; computes order_count, unique_customers,
gross_revenue. Idempotent: MERGE INTO on (order_date, department) natural key.

Gold schema:
  order_date DATE, department STRING,
  order_count BIGINT, unique_customers BIGINT, gross_revenue DECIMAL(18,2),
  avg_order_value DECIMAL(12,2),
  _gold_timestamp TIMESTAMP
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

from utils.delta_utils import (
    get_table_version,
    optimize_table,
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
SILVER_ORDERS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/orders/"
SILVER_ITEMS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/order_items/"
SILVER_PRODUCTS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/products/"
GOLD_PATH = f"s3://{LAKEHOUSE}/{args['GOLD_PREFIX']}/daily_revenue/"
DB_GOLD = args["CATALOG_DATABASE_GOLD"]
EXECUTION_DATE = args["EXECUTION_DATE"]

# ── Read Silver ───────────────────────────────────────────────────────────────

orders_df = spark.read.format("delta").load(SILVER_ORDERS_PATH)
items_df = spark.read.format("delta").load(SILVER_ITEMS_PATH)
products_df = (
    spark.read.format("delta").load(SILVER_PRODUCTS_PATH)
    .filter(F.col("is_current") == True)
    .select("product_id", "department")
)

# ── Filter to execution month for targeted refresh ────────────────────────────

exec_year = int(EXECUTION_DATE[:4])
exec_month = int(EXECUTION_DATE[5:7])

orders_filtered = orders_df.filter(
    (F.col("order_year") == exec_year) & (F.col("order_month") == exec_month)
)

# ── Join order_items → products to get department ─────────────────────────────

items_with_dept = items_df.join(products_df, on="product_id", how="left")

# Aggregate items: one row per (order_id, department) with item count
order_dept = (
    items_with_dept
    .groupBy("order_id", "department")
    .agg(F.count("id").alias("item_count"))
)

# Join orders to get order_date, user_id, total_amount
orders_with_dept = orders_filtered.join(order_dept, on="order_id", how="left").fillna(
    {"department": "UNKNOWN"}
)

# ── Aggregate to Gold ─────────────────────────────────────────────────────────

gold_df = (
    orders_with_dept
    .groupBy("order_date", "department")
    .agg(
        F.countDistinct("order_id").alias("order_count"),
        F.countDistinct("user_id").alias("unique_customers"),
        F.sum("total_amount").cast(DecimalType(18, 2)).alias("gross_revenue"),
    )
    .withColumn(
        "avg_order_value",
        (F.col("gross_revenue") / F.col("order_count")).cast(DecimalType(12, 2)),
    )
    .withColumn("order_year", F.year(F.col("order_date")))
    .withColumn("order_month", F.month(F.col("order_date")))
    .withColumn("_gold_timestamp", F.current_timestamp())
)

# ── Write Gold — MERGE on natural key (order_date, department) ────────────────

if not table_exists(spark, GOLD_PATH):
    (
        gold_df
        .write.format("delta")
        .partitionBy("order_year", "order_month")
        .mode("overwrite")
        .save(GOLD_PATH)
    )
else:
    from delta.tables import DeltaTable

    gold_table = DeltaTable.forPath(spark, GOLD_PATH)
    merge_condition = (
        "target.order_date = source.order_date AND target.department = source.department"
    )
    (
        gold_table.alias("target")
        .merge(gold_df.alias("source"), merge_condition)
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )

optimize_table(spark, GOLD_PATH, zorder_cols=["order_date", "department"])
register_table_in_catalog(spark, DB_GOLD, "daily_revenue", GOLD_PATH)
print(f"[Gold] daily_revenue: version {get_table_version(spark, GOLD_PATH)} | {exec_year}-{exec_month:02d}")

job.commit()

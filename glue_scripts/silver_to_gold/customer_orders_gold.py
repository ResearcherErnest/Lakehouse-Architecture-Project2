"""
customer_orders_gold.py
Computes customer-level lifetime value metrics from Silver orders.
Full recompute per execution month — replaceWhere on snapshot_year + snapshot_month
so each run produces a fresh monthly customer snapshot without accumulating stale rows.

Gold schema:
  user_id BIGINT,
  total_orders BIGINT, total_spend DECIMAL(18,2),
  avg_order_value DECIMAL(12,2),
  avg_days_between_orders DOUBLE,
  first_order_date DATE, last_order_date DATE,
  snapshot_year INT, snapshot_month INT,
  _gold_timestamp TIMESTAMP
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType
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
SILVER_ORDERS_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/orders/"
GOLD_PATH = f"s3://{LAKEHOUSE}/{args['GOLD_PREFIX']}/customer_orders/"
DB_GOLD = args["CATALOG_DATABASE_GOLD"]
EXECUTION_DATE = args["EXECUTION_DATE"]

exec_year = int(EXECUTION_DATE[:4])
exec_month = int(EXECUTION_DATE[5:7])

# ── Read all Silver orders (LTV is cumulative, not monthly-scoped) ─────────────

orders_df = spark.read.format("delta").load(SILVER_ORDERS_PATH)

# ── Compute avg days between orders per customer ──────────────────────────────

user_window = Window.partitionBy("user_id").orderBy("order_date")

orders_with_lag = orders_df.withColumn(
    "prev_order_date", F.lag("order_date").over(user_window)
).withColumn(
    "days_since_prev",
    F.datediff(F.col("order_date"), F.col("prev_order_date")).cast("double"),
)

# ── Aggregate per customer ────────────────────────────────────────────────────

customer_agg = (
    orders_with_lag
    .groupBy("user_id")
    .agg(
        F.countDistinct("order_id").alias("total_orders"),
        F.sum("total_amount").cast(DecimalType(18, 2)).alias("total_spend"),
        F.avg("days_since_prev").alias("avg_days_between_orders"),
        F.min("order_date").alias("first_order_date"),
        F.max("order_date").alias("last_order_date"),
    )
    .withColumn(
        "avg_order_value",
        (F.col("total_spend") / F.col("total_orders")).cast(DecimalType(12, 2)),
    )
    .withColumn("avg_days_between_orders", F.round(F.col("avg_days_between_orders"), 2))
)

# ── Attach snapshot period and timestamp ──────────────────────────────────────

gold_df = (
    customer_agg
    .withColumn("snapshot_year", F.lit(exec_year))
    .withColumn("snapshot_month", F.lit(exec_month))
    .withColumn("_gold_timestamp", F.current_timestamp())
)

# ── Write Gold — idempotent snapshot overwrite ────────────────────────────────

replace_where = f"snapshot_year = {exec_year} AND snapshot_month = {exec_month}"

if not table_exists(spark, GOLD_PATH):
    (
        gold_df
        .write.format("delta")
        .partitionBy("snapshot_year", "snapshot_month")
        .mode("overwrite")
        .save(GOLD_PATH)
    )
else:
    overwrite_partition(
        source_df=gold_df,
        delta_path=GOLD_PATH,
        replace_where=replace_where,
        partition_cols=["snapshot_year", "snapshot_month"],
    )

optimize_table(spark, GOLD_PATH, zorder_cols=["total_spend", "total_orders"])
register_table_in_catalog(spark, DB_GOLD, "customer_orders", GOLD_PATH)
print(f"[Gold] customer_orders: version {get_table_version(spark, GOLD_PATH)} | snapshot {exec_year}-{exec_month:02d}")

job.commit()

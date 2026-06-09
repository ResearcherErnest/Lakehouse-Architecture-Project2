"""
orders_silver.py
Transforms Bronze orders into Silver.
- Type-casts all columns
- Deduplicates on order_id (latest ingestion wins)
- Derives order_year, order_month, day_of_week
- Idempotent overwrites via replaceWhere on order_year + order_month

Bronze schema: order_num, order_id, user_id, order_timestamp, total_amount, date
               + 4 _system columns (_ingestion_timestamp, _source_file, etc.)
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType, LongType, TimestampType

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
        "CATALOG_DATABASE_BRONZE",
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
BRONZE_PATH = f"s3://{LAKEHOUSE}/{args['BRONZE_PREFIX']}/orders/"
SILVER_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/orders/"
DB_SILVER = args["CATALOG_DATABASE_SILVER"]
EXECUTION_DATE = args["EXECUTION_DATE"]

# ── Read Bronze ───────────────────────────────────────────────────────────────

bronze_df = spark.read.format("delta").load(BRONZE_PATH)

# ── Type-cast ─────────────────────────────────────────────────────────────────

typed_df = (
    bronze_df
    .withColumn("order_id", F.col("order_id").cast(LongType()))
    .withColumn("order_num", F.col("order_num").cast(LongType()))
    .withColumn("user_id", F.col("user_id").cast(LongType()))
    .withColumn(
        "order_timestamp",
        F.to_timestamp(F.col("order_timestamp"), "yyyy-MM-dd HH:mm:ss"),
    )
    .withColumn("total_amount", F.col("total_amount").cast(DecimalType(12, 2)))
    .withColumn("order_date", F.to_date(F.col("date"), "yyyy-MM-dd"))
)

# ── Validate ──────────────────────────────────────────────────────────────────

valid_df = (
    typed_df
    .filter(F.col("order_id").isNotNull())
    .filter(F.col("user_id").isNotNull())
    .filter(F.col("total_amount") > 0)
)

# ── Deduplicate: keep the record ingested most recently per order_id ──────────

deduped_df = (
    valid_df
    .withColumn(
        "_row_rank",
        F.row_number().over(
            __import__("pyspark.sql.window", fromlist=["Window"])
            .Window.partitionBy("order_id")
            .orderBy(F.col("_ingestion_timestamp").desc())
        ),
    )
    .filter(F.col("_row_rank") == 1)
    .drop("_row_rank")
)

# ── Derive temporal features ──────────────────────────────────────────────────

enriched_df = (
    deduped_df
    .withColumn("order_year", F.year(F.col("order_date")))
    .withColumn("order_month", F.month(F.col("order_date")))
    .withColumn("day_of_week", F.dayofweek(F.col("order_date")))
    .withColumn("_silver_timestamp", F.current_timestamp())
    .drop("date")
)

# ── Derive partition filter from execution date (YYYY-MM-DD) ──────────────────

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

optimize_table(spark, SILVER_PATH, zorder_cols=["order_date", "user_id"])
register_table_in_catalog(spark, DB_SILVER, "orders", SILVER_PATH)
print(f"[Silver] orders: version {get_table_version(spark, SILVER_PATH)} | partition {replace_where}")

job.commit()

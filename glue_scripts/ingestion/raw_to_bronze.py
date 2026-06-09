"""
raw_to_bronze.py
Reads raw CSV files from the landing bucket and writes them as Delta Lake tables
in the Bronze layer. Adds system metadata columns. Glue bookmarks prevent
re-processing files already ingested in previous runs.
"""

import sys
from datetime import datetime

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

from utils.delta_utils import append_to_delta, get_spark_session, register_table_in_catalog

# ── Job parameters ────────────────────────────────────────────────────────────

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "RAW_BUCKET",
        "LAKEHOUSE_BUCKET",
        "BRONZE_PREFIX",
        "CATALOG_DATABASE_BRONZE",
        "EXECUTION_DATE",
    ],
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

RAW_BUCKET = args["RAW_BUCKET"]
LAKEHOUSE_BUCKET = args["LAKEHOUSE_BUCKET"]
BRONZE_PREFIX = args["BRONZE_PREFIX"]
DB_BRONZE = args["CATALOG_DATABASE_BRONZE"]
EXECUTION_DATE = args["EXECUTION_DATE"]

# ── Source paths ──────────────────────────────────────────────────────────────

SOURCES = {
    "products":     f"s3://{RAW_BUCKET}/uploads/products.csv",
    "orders":       f"s3://{RAW_BUCKET}/uploads/orders_apr_2025.csv",
    "order_items":  f"s3://{RAW_BUCKET}/uploads/order_items_apr_2025.csv",
}

# ── Ingestion ─────────────────────────────────────────────────────────────────

ingestion_ts = datetime.utcnow().isoformat()

for domain, source_path in SOURCES.items():
    bronze_path = f"s3://{LAKEHOUSE_BUCKET}/{BRONZE_PREFIX}/{domain}/"

    # Read raw CSV — all columns as strings; no schema inference to preserve fidelity
    raw_df = (
        spark.read.format("csv")
        .option("header", "true")
        .option("inferSchema", "false")
        .option("encoding", "UTF-8")
        .load(source_path)
    )

    # Add Bronze system columns
    bronze_df = (
        raw_df
        .withColumn("_ingestion_timestamp", F.lit(ingestion_ts))
        .withColumn("_source_file", F.lit(source_path))
        .withColumn("_source_partition_date", F.lit(EXECUTION_DATE[:10]))
        .withColumn("_job_run_id", F.lit(args["JOB_NAME"]))
    )

    append_to_delta(
        source_df=bronze_df,
        delta_path=bronze_path,
        partition_cols=["_source_partition_date"],
    )

    register_table_in_catalog(
        spark=spark,
        database=DB_BRONZE,
        table_name=domain,
        delta_path=bronze_path,
    )

    print(f"[Bronze] {domain}: {bronze_df.count()} rows written to {bronze_path}")

job.commit()

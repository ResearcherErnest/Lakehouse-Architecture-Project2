"""
products_silver.py
Transforms Bronze products into Silver with SCD Type 2.
New products are inserted; changed products close the old record and insert a new one.
Schema: product_id, department_id, department, product_name,
        valid_from, valid_to, is_current, _record_hash, _silver_timestamp
"""

import sys
from datetime import datetime

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType

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
BRONZE_PATH = f"s3://{LAKEHOUSE}/{args['BRONZE_PREFIX']}/products/"
SILVER_PATH = f"s3://{LAKEHOUSE}/{args['SILVER_PREFIX']}/products/"
DB_SILVER = args["CATALOG_DATABASE_SILVER"]
NOW = datetime.utcnow().isoformat()

# ── Read Bronze ───────────────────────────────────────────────────────────────

bronze_df = spark.read.format("delta").load(BRONZE_PATH)

# ── Type-cast and clean ───────────────────────────────────────────────────────

cleaned_df = (
    bronze_df
    .withColumn("product_id", F.col("product_id").cast(IntegerType()))
    .withColumn("department_id", F.col("department_id").cast(IntegerType()))
    .withColumn("department", F.upper(F.trim(F.col("department"))))
    .withColumn("product_name", F.trim(F.col("product_name")))
    .filter(F.col("product_id").isNotNull())
    .filter(F.col("product_name") != "")
    .dropDuplicates(["product_id"])
)

# Record hash for change detection (SCD2 trigger)
incoming_df = cleaned_df.withColumn(
    "_record_hash",
    F.md5(F.concat_ws("|", F.col("department_id"), F.col("department"), F.col("product_name"))),
)

# ── SCD Type 2 MERGE ──────────────────────────────────────────────────────────

if not table_exists(spark, SILVER_PATH):
    # Initial load — all records are current
    (
        incoming_df
        .withColumn("valid_from", F.lit(NOW))
        .withColumn("valid_to", F.lit(None).cast("string"))
        .withColumn("is_current", F.lit(True))
        .withColumn("_silver_timestamp", F.lit(NOW))
        .write.format("delta")
        .partitionBy("department")
        .mode("overwrite")
        .save(SILVER_PATH)
    )
else:
    from delta.tables import DeltaTable

    silver_table = DeltaTable.forPath(spark, SILVER_PATH)

    # Step 1: expire changed current records
    silver_table.alias("target").merge(
        incoming_df.alias("source"),
        "target.product_id = source.product_id AND target.is_current = true AND target._record_hash != source._record_hash",
    ).whenMatchedUpdate(
        set={"is_current": F.lit(False), "valid_to": F.lit(NOW)}
    ).execute()

    # Step 2: insert new and changed records
    existing_current = (
        silver_table.toDF()
        .filter(F.col("is_current") == True)
        .select("product_id", "_record_hash")
    )
    new_or_changed = incoming_df.join(
        existing_current,
        on=(
            (incoming_df.product_id == existing_current.product_id)
            & (incoming_df._record_hash == existing_current._record_hash)
        ),
        how="left_anti",
    )
    (
        new_or_changed
        .withColumn("valid_from", F.lit(NOW))
        .withColumn("valid_to", F.lit(None).cast("string"))
        .withColumn("is_current", F.lit(True))
        .withColumn("_silver_timestamp", F.lit(NOW))
        .write.format("delta")
        .partitionBy("department")
        .mode("append")
        .save(SILVER_PATH)
    )

optimize_table(spark, SILVER_PATH)
register_table_in_catalog(spark, DB_SILVER, "products", SILVER_PATH)
print(f"[Silver] products: version {get_table_version(spark, SILVER_PATH)} written.")

job.commit()

"""
Shared Delta Lake utilities for the e-commerce lakehouse PySpark jobs.
All functions assume the SparkSession is already configured with Delta extensions.
"""

import logging
from typing import List, Optional

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession

logger = logging.getLogger(__name__)


def get_spark_session(app_name: str) -> SparkSession:
    """Return an existing SparkSession configured with Delta Lake extensions."""
    return (
        SparkSession.builder.appName(app_name)
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .getOrCreate()
    )


def table_exists(spark: SparkSession, path: str) -> bool:
    """Return True if a Delta table already exists at the given S3 path."""
    try:
        DeltaTable.forPath(spark, path)
        return True
    except Exception:
        return False


def upsert_to_delta(
    spark: SparkSession,
    source_df: DataFrame,
    delta_path: str,
    merge_condition: str,
    update_set: dict,
    insert_values: dict,
) -> None:
    """
    Merge source_df into an existing Delta table using the provided condition.
    Creates the table from source_df if it does not yet exist.
    """
    if not table_exists(spark, delta_path):
        logger.info("Delta table not found at %s — performing initial write.", delta_path)
        source_df.write.format("delta").mode("overwrite").save(delta_path)
        return

    delta_table = DeltaTable.forPath(spark, delta_path)
    (
        delta_table.alias("target")
        .merge(source_df.alias("source"), merge_condition)
        .whenMatchedUpdate(set=update_set)
        .whenNotMatchedInsert(values=insert_values)
        .execute()
    )
    logger.info("Upsert complete for %s.", delta_path)


def append_to_delta(
    source_df: DataFrame,
    delta_path: str,
    partition_cols: Optional[List[str]] = None,
) -> None:
    """Append source_df to a Delta table, creating it if it does not exist."""
    writer = source_df.write.format("delta").mode("append")
    if partition_cols:
        writer = writer.partitionBy(*partition_cols)
    writer.save(delta_path)
    logger.info("Appended %d rows to %s.", source_df.count(), delta_path)


def overwrite_partition(
    source_df: DataFrame,
    delta_path: str,
    replace_where: str,
    partition_cols: Optional[List[str]] = None,
) -> None:
    """
    Idempotently overwrite a specific partition using replaceWhere.
    Safe to re-run: produces identical output regardless of how many times called.
    """
    writer = (
        source_df.write.format("delta")
        .mode("overwrite")
        .option("replaceWhere", replace_where)
    )
    if partition_cols:
        writer = writer.partitionBy(*partition_cols)
    writer.save(delta_path)
    logger.info("Partition overwrite complete for %s (filter: %s).", delta_path, replace_where)


def optimize_table(spark: SparkSession, delta_path: str, zorder_cols: Optional[List[str]] = None) -> None:
    """
    Run OPTIMIZE (and optionally ZORDER BY) on a Delta table to compact small files
    and improve Athena query performance by 40-70%.
    """
    if zorder_cols:
        cols = ", ".join(zorder_cols)
        spark.sql(f"OPTIMIZE delta.`{delta_path}` ZORDER BY ({cols})")
        logger.info("OPTIMIZE + ZORDER BY (%s) complete for %s.", cols, delta_path)
    else:
        spark.sql(f"OPTIMIZE delta.`{delta_path}`")
        logger.info("OPTIMIZE complete for %s.", delta_path)


def vacuum_table(spark: SparkSession, delta_path: str, retention_hours: int = 168) -> None:
    """
    Remove old Delta versions beyond the retention window.
    Default 168 hours (7 days) preserves time-travel for one week.
    Do NOT reduce below 168h in production without disabling the retention check.
    """
    spark.sql(
        f"VACUUM delta.`{delta_path}` RETAIN {retention_hours} HOURS"
    )
    logger.info("VACUUM complete for %s (retention: %dh).", delta_path, retention_hours)


def get_table_version(spark: SparkSession, delta_path: str) -> int:
    """Return the current Delta table version number for audit logging."""
    delta_table = DeltaTable.forPath(spark, delta_path)
    history = delta_table.history(1)
    return history.select("version").collect()[0]["version"]


def register_table_in_catalog(
    spark: SparkSession,
    database: str,
    table_name: str,
    delta_path: str,
) -> None:
    """Register a Delta table in the Glue Data Catalog using a CREATE TABLE IF NOT EXISTS."""
    spark.sql(f"CREATE DATABASE IF NOT EXISTS {database}")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {database}.{table_name}
        USING DELTA
        LOCATION '{delta_path}'
    """)
    logger.info("Registered %s.%s -> %s in Glue catalog.", database, table_name, delta_path)

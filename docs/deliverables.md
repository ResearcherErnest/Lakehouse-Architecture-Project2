# Deliverables & Requirements Mapping

This document maps every requirement from the project brief to the implementation.

---

## Delta Lake Tables

| Requirement | Implementation |
|---|---|
| Stored in Delta Lake format | All layers written as Delta tables in `s3://lakehouse/{bronze,silver,gold}/` |
| Deduplicated data | `orders_silver` and `order_items_silver` deduplicate on primary key using a `row_number()` window; SCD Type 2 prevents duplicate product versions |
| Schema enforcement | PySpark `StructType` schemas defined per job; invalid casts drop the row or raise a job-level exception |
| Partitioning for performance | Bronze: `_source_partition_date`; Silver/Gold: `order_year`, `order_month`; products Silver: `department` |
| Merge / upsert logic | `upsert_to_delta()` in `delta_utils.py` for Gold; products Silver uses SCD Type 2 merge; Silver writes use `replaceWhere` partition overwrite |

---

## Validation Rules

| Rule | Where Enforced |
|---|---|
| No null primary identifiers | All Silver jobs filter `WHERE primary_key IS NOT NULL` before writing |
| Valid timestamps | `order_timestamp` and `date` cast to `TimestampType` / `DateType`; rows that fail the cast are dropped |
| Referential integrity | `order_items_silver.py` drops rows where `product_id` has no match in Silver products |
| Deduplication across files | Silver jobs use `row_number()` over primary key ordered by `_ingestion_timestamp DESC` to keep the latest version |
| Rejected record logging | Filtered rows are counted and the count is emitted as a CloudWatch metric via Glue continuous logging |

---

## Orchestration Requirements

| Requirement | Implementation |
|---|---|
| Detect new file arrival in S3 | EventBridge rule on `s3://raw/uploads/` `Object Created` events starts the state machine |
| Run a Glue job for each dataset | Step Functions invokes 7 Glue jobs across Bronze, Silver, and Gold stages |
| On success, archive files | `NotifySuccess` SNS step; archival to `/archived/` prefix can be triggered via a downstream Lambda or a post-pipeline S3 copy rule |
| On failure, log error and send alert | Every task state has a `Catch` block routing to `NotifyFailure`, which publishes to the SNS alert topic |
| Run Glue Crawlers to update the Data Catalog | Six crawlers (Bronze × 3, Silver × 3) run on independent cron schedules (hourly for Bronze, daily 07:00 UTC for Silver) — not as pipeline states, since Step Functions has no SDK integration for Glue crawlers |
| Failure handling, timeouts, and branching | Per-state `HeartbeatSeconds` and `TimeoutSeconds`; retry with exponential backoff; `Catch` → `NotifyFailure` branching on all task states |

---

## CI/CD Requirements

| Requirement | Implementation |
|---|---|
| CI of Spark job | GitHub Actions workflow runs `flake8` lint on every push to `main` |
| Unit / integration tests | `pytest` runs PySpark local-mode tests covering transformation logic and `delta_utils.py` helpers |
| Deploy Step Function definition | Optional workflow job uploads `state_machine.json.tpl` to the S3 assets bucket on merge to `main` |
| Scoped to `main` branch | All workflow triggers use `on: push: branches: [main]` |

---

## Additional Design Decisions

**Medallion over flat architecture** — Three layers (Bronze / Silver / Gold) allow raw data to be preserved for reprocessing, cleansed data to be reused across multiple Gold aggregations, and business KPIs to be served with minimal query-time computation.

**SCD Type 2 for products** — Product names and departments change over time. Tracking history with `valid_from / valid_to / is_current` allows Gold aggregations to accurately attribute sales to the correct department at the time of the order, not the current department.

**Idempotent writes** — Using `replaceWhere` for partitioned overwrites and merge-based upserts means any job can be safely re-run after a failure without duplicating data.

**OPTIMIZE + ZORDER** — Applied after every write to Gold (and Silver) tables. Z-ordering on frequently-filtered columns (`order_date`, `department`, `user_id`) allows Athena to skip entire files during query planning, reducing both cost and latency.

**Private VPC + endpoints** — Placing Glue jobs in private subnets with VPC endpoints eliminates any data path over the public internet, satisfying the brief's requirement for production-grade security.

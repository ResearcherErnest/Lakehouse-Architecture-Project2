# Architecture

## Overview

The system implements a **medallion architecture** (Bronze → Silver → Gold) on AWS. Raw e-commerce CSVs land in S3, are progressively refined through three Delta Lake layers, and are exposed for SQL analytics via Athena. All compute runs inside a private VPC with no internet egress.

## Diagram

```
                         ┌──────────────────────────────────────────────────┐
                         │                       AWS VPC                   │
                         │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
CSV Files ──► S3 Raw ───►│  │  Glue    │  │  Glue    │  │  Glue    │       │
                         │  │ raw→brz  │  │ brz→slv  │  │ slv→gld  │       │
                         │  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
                         │       │              │              │             │
                         └───────┼──────────────┼──────────────┼────────────┘
                                 │              │              │
                            S3 Bronze      S3 Silver       S3 Gold
                           (Delta tables) (Delta tables) (Delta tables)
                                 │              │              │
                         ┌───────▼──────────────▼──────────────▼───────────┐
                         │         Glue Data Catalog + Lake Formation       │
                         └───────────────────────┬──────────────────────────┘
                                                 │
                                          Amazon Athena
                                     (SQL analytics queries)
```

## Medallion Layers

| Layer | S3 Prefix | Description |
|---|---|---|
| **Bronze** | `s3://lakehouse/bronze/` | Raw CSV data replicated as-is with system metadata columns |
| **Silver** | `s3://lakehouse/silver/` | Cleansed, typed, deduplicated; SCD Type 2 for product dimension |
| **Gold** | `s3://lakehouse/gold/` | Aggregated KPIs: daily revenue, product performance, customer LTV |

## Pipeline Flow

```
EventBridge (daily cron 06:00 UTC / S3 Object Created event)
        │
        ▼
Step Functions Standard State Machine
        │
        ├─► IngestRawToBronze          ← raw_to_bronze Glue job
        │        │ (on error) ──────────────────────────────────► NotifyFailure (SNS)
        │
        ├─► BronzeToSilverTransforms [PARALLEL]
        │       ├─ ProductsSilver       ← products_silver Glue job
        │       ├─ OrdersSilver         ← orders_silver Glue job
        │       └─ OrderItemsSilver     ← order_items_silver Glue job
        │
        ├─► SilverToGoldTransforms [PARALLEL]
        │       ├─ DailyRevenueGold     ← daily_revenue_gold Glue job
        │       ├─ ProductPerformance   ← product_performance_gold Glue job
        │       └─ CustomerOrders       ← customer_orders_gold Glue job
        │
        └─► NotifySuccess              ← SNS topic
```

Every stage has a `Catch` block routing failures to `NotifyFailure` (SNS). Retries use exponential backoff with configurable `HeartbeatSeconds` and `TimeoutSeconds`.

## AWS Services

| Category | Service | Purpose |
|---|---|---|
| Compute | AWS Glue 4.0 (PySpark 3.3) | ETL jobs across all three layers |
| Compute | AWS Step Functions (Standard) | Pipeline orchestration |
| Storage | Amazon S3 (4 buckets) | Raw, lakehouse, Glue assets, Athena results |
| Storage | Delta Lake | ACID tables with time-travel |
| Catalog | AWS Glue Data Catalog | Schema registry:3 databases |
| Governance | AWS Lake Formation | Fine-grained table & column permissions |
| Query | Amazon Athena | Interactive SQL on Silver & Gold layers |
| Networking | Amazon VPC | Private subnets across 3 AZs |
| Networking | VPC Endpoints | Private access to S3, Glue, KMS, CloudWatch, Step Functions |
| Security | AWS KMS | Customer-managed key (CMK) for all data at rest |
| Security | AWS IAM | Least-privilege roles for Glue, crawlers, Step Functions, Lake Formation |
| Orchestration | Amazon EventBridge | Daily schedule + S3-event triggers |
| Alerting | Amazon SNS | Pipeline success / failure notifications |
| Monitoring | Amazon CloudWatch | Logs, alarms, dashboards |
| Cost | AWS Budgets | Monthly spend limit with threshold alerts |

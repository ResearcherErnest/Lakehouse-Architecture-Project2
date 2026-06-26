# Monitoring & Cost

## Observability Stack

```mermaid
flowchart TB
    subgraph SOURCES["📡 Telemetry Sources"]
        direction LR
        GJ["Glue ETL Jobs\n7 jobs — continuous logging"]
        GC["Glue Crawlers\n6 crawlers — run logs"]
        SF["Step Functions\nExecution history + state transitions"]
        S3M["S3 Buckets\nBucketSizeBytes per bucket"]
        AM["Amazon Athena\nDataScannedInBytes per workgroup"]
    end

    subgraph CW["Amazon CloudWatch"]
        subgraph LOGS["Log Groups — 30d retention · KMS encrypted"]
            direction LR
            LG1["/aws-glue/jobs/output"]
            LG2["/aws-glue/jobs/error"]
            LG3["/aws-glue/crawlers"]
            LG4["/aws/states/ecom-lakehouse"]
        end
        subgraph ALARMS["Alarms — 9 total"]
            direction LR
            A1["Glue job failure\n×7 — one per ETL job"]
            A2["SFN ExecutionsFailed >= 1"]
            A3["Pipeline SLA breach\np99 > threshold"]
        end
        DASH["Dashboard — ecom-lakehouse-pipeline\n5 widgets · 7-day window\nExecutions · DPU hours · S3 storage · Athena scanned · Crawler times"]
    end

    SNS_T["SNS Topic\necom-lakehouse-pipeline-alerts"]
    EMAIL["Email subscriber\nconfigured via sns_alert_email variable"]
    BUD["AWS Budgets\n$500/month default\nAlerts at 80% and 100%"]

    GJ & GC --> LOGS
    SF --> LOGS
    GJ & GC & SF & S3M & AM --> DASH
    GJ & SF --> ALARMS
    ALARMS -->|"threshold breach"| SNS_T
    BUD -->|"budget alert"| SNS_T
    SNS_T --> EMAIL
```

---

## CloudWatch Dashboard

A single dashboard (`ecom-lakehouse-pipeline`) with five widgets:

| Widget | Metric | Window |
|---|---|---|
| Pipeline executions | Step Functions `ExecutionsStarted` / `ExecutionsSucceeded` / `ExecutionsFailed` | Last 7 days |
| Glue DPU hours | Per-job `glue.driver.ExecutorRunTime` | Last 7 days |
| S3 storage | `BucketSizeBytes` per bucket | Last 7 days |
| Athena data scanned | `DataScannedInBytes` per workgroup | Last 7 days |
| Crawler run times | Crawler `ElapsedTime` | Last 7 days |

## Alarms

| Alarm | Metric | Condition | Action |
|---|---|---|---|
| Glue job failure (×7) | `glue.driver.aggregate.numFailedTasks` per job | >= 1 | SNS alert |
| Pipeline SLA breach | Step Functions p99 `ExecutionTime` | > configurable threshold | SNS alert |
| Pipeline execution failure | Step Functions `ExecutionsFailed` | >= 1 | SNS alert |

All alarms publish to the `ecom-lakehouse-pipeline-alerts` SNS topic. Subscribe an email address via the `sns_alert_email` Terraform variable.

## CloudWatch Log Groups

| Log Group | Retention | Source |
|---|---|---|
| `/aws-glue/jobs/output` | 30 days | Glue job stdout |
| `/aws-glue/jobs/error` | 30 days | Glue job stderr |
| `/aws-glue/crawlers` | 30 days | Crawler run logs |
| `/aws/states/ecom-lakehouse` | 30 days | Step Functions execution history |

All log groups are encrypted with the project KMS CMK.

## Cost Controls

**Athena scan limits**

| Workgroup | Max bytes per query |
|---|---|
| `primary` (analysts) | 10 GB |
| `engineering` | 50 GB |

Queries that would exceed the limit are cancelled before execution.

**S3 lifecycle policies**

| Bucket | Rule |
|---|---|
| Raw | Objects → S3 Infrequent Access at 30 days → S3 Glacier at 90 days |
| Lakehouse (Bronze) | Objects → S3 Intelligent-Tiering |
| Athena results | Objects expire (deleted) after 7 days |

**Delta OPTIMIZE + ZORDER**

All Gold and Silver tables are compacted and Z-ordered after each write. This reduces the number of files Athena must scan by co-locating frequently queried columns, typically cutting Athena costs by 40–70% compared to unoptimised Delta tables.

**AWS Budgets**

A monthly budget is created with the `monthly_budget_usd` variable (default $500). Email notifications are sent at 80% and 100% of the threshold.

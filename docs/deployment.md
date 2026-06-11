# Deployment Guide

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS CLI configured with credentials that can create all services in this project
- Python 3.10+ (to run or test Glue scripts locally)

---

## Step 1 — Bootstrap Remote State

Create the S3 bucket and DynamoDB lock table referenced in `terraform/backend.tf` before the first `terraform init`.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3api create-bucket \
  --bucket "ecom-lakehouse-tfstate-${ACCOUNT_ID}" \
  --region us-east-1

aws dynamodb create-table \
  --table-name ecom-lakehouse-tfstate-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## Step 2 — Upload Glue Scripts

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ASSETS_BUCKET="ecom-lakehouse-glue-assets-${ACCOUNT_ID}"

aws s3 cp glue_scripts/ s3://${ASSETS_BUCKET}/scripts/ --recursive
```

---

## Step 3 — Initialise and Apply Terraform

```bash
cd terraform

terraform init \
  -backend-config="bucket=ecom-lakehouse-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=lakehouse/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan \
  -var="aws_account_id=${ACCOUNT_ID}" \
  -var="sns_alert_email=your@email.com" \
  -out=tfplan

terraform apply tfplan
```

---

## Step 4 — Upload Sample Data and Trigger the Pipeline

```bash
RAW_BUCKET="ecom-lakehouse-raw-${ACCOUNT_ID}"

aws s3 cp data/products.csv              s3://${RAW_BUCKET}/uploads/
aws s3 cp data/orders_apr_2025.csv       s3://${RAW_BUCKET}/uploads/
aws s3 cp data/order_items_apr_2025.csv  s3://${RAW_BUCKET}/uploads/
```

The S3 upload event triggers EventBridge, which starts the Step Functions state machine automatically.

To trigger manually:

```bash
STATE_MACHINE_ARN=$(terraform -chdir=terraform output -raw step_functions_arn)

aws stepfunctions start-execution \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --input '{"execution_date":"2025-04-01"}'
```

---

## Step 5 — Verify the Deployment

Run the checks below after the pipeline has been triggered (allow ~5–10 minutes for all Glue jobs to complete).

### 5a — Check the Step Functions execution

```bash
STATE_MACHINE_ARN=$(terraform -chdir=terraform output -raw step_functions_arn)

# List the most recent execution
aws stepfunctions list-executions \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --max-results 1 \
  --query "executions[0].{status:status,start:startDate,stop:stopDate}"
```

Expected output: `"status": "SUCCEEDED"`. If the status is `FAILED`, fetch the execution ARN and inspect events:

```bash
EXEC_ARN=$(aws stepfunctions list-executions \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --max-results 1 \
  --query "executions[0].executionArn" --output text)

aws stepfunctions get-execution-history \
  --execution-arn "${EXEC_ARN}" \
  --query "events[?type=='ExecutionFailed' || type=='TaskFailed']"
```

### 5b — Check each Glue job ran successfully

```bash
for JOB in raw_to_bronze products_silver orders_silver order_items_silver \
           daily_revenue_gold product_performance_gold customer_orders_gold; do
  aws glue get-job-runs --job-name "${JOB}" --max-results 1 \
    --query "JobRuns[0].{job:JobName,state:JobRunState,started:StartedOn,duration:ExecutionTime}" \
    --output table
done
```

All jobs should show `JobRunState: SUCCEEDED`. A `FAILED` state means the job error is in CloudWatch:

```bash
aws logs filter-log-events \
  --log-group-name "/aws-glue/jobs/error" \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --query "events[*].message" --output text
```

### 5c — Confirm data landed in each layer

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAKEHOUSE="s3://ecom-lakehouse-lakehouse-${ACCOUNT_ID}"

for PREFIX in bronze/products bronze/orders bronze/order_items \
              silver/products silver/orders silver/order_items \
              gold/daily_revenue gold/product_performance gold/customer_orders; do
  COUNT=$(aws s3 ls "${LAKEHOUSE}/${PREFIX}/" --recursive \
    | grep -c '\.parquet' || true)
  echo "${PREFIX}: ${COUNT} parquet file(s)"
done
```

Each prefix should report at least one Parquet file. Missing files indicate the relevant Glue job did not write output — check job logs in step 5b.

### 5d — Query Gold data with Athena

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Spot-check the daily_revenue Gold table
aws athena start-query-execution \
  --query-string "SELECT * FROM ecom-lakehouse_gold.daily_revenue ORDER BY order_date DESC LIMIT 5;" \
  --work-group "engineering" \
  --result-configuration "OutputLocation=s3://ecom-lakehouse-athena-results-${ACCOUNT_ID}/" \
  --query "QueryExecutionId" --output text
```

Then retrieve results (replace `<QueryExecutionId>` with the ID returned above):

```bash
aws athena get-query-results \
  --query-execution-id "<QueryExecutionId>" \
  --query "ResultSet.Rows[*].Data[*].VarCharValue"
```

### 5e — Confirm CloudWatch dashboard is populated

```bash
aws cloudwatch get-dashboard \
  --dashboard-name "ecom-lakehouse" \
  --query "DashboardBody" --output text | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d[\"widgets\"])} widgets found')"
```

Should report `5 widgets found`. Open the dashboard in the console under **CloudWatch → Dashboards → ecom-lakehouse** to visually confirm the pipeline execution and DPU metrics are populated.

---

## Configuration Reference

All tuneable parameters are in `terraform/variables.tf`:

| Variable | Default | Description |
|---|---|---|
| `project_name` | `ecom-lakehouse` | Prefix applied to all resource names |
| `aws_region` | `us-east-1` | Deployment region |
| `aws_account_id` | — | **Required.** Your AWS account ID |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `availability_zones` | 3 AZs | AZs for private subnets |
| `glue_worker_type` | `G.1X` | `G.1X` for dev/lab, `G.2X` for production |
| `glue_num_workers` | `2` | Workers per Glue job |
| `log_retention_days` | `30` | CloudWatch log retention in days |
| `monthly_budget_usd` | `500` | AWS Budget monthly ceiling in USD |
| `sns_alert_email` | — | Optional email address for pipeline alerts |
| `schedule_expression` | `cron(0 6 * * ? *)` | EventBridge daily trigger (UTC) |

---

## Teardown

```bash
cd terraform
terraform destroy -var="aws_account_id=${ACCOUNT_ID}"
```

Note: S3 buckets with versioning enabled must be emptied (including all versions and delete markers) before Terraform can destroy them.

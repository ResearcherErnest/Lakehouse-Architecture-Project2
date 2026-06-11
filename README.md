# E-Commerce Data Lakehouse on AWS

A production-grade Lakehouse architecture for an e-commerce platform on AWS, ingesting raw transactional CSVs from S3, transforming them through a **Bronze → Silver → Gold** medallion pipeline using Delta Lake on AWS Glue, and exposing analytics-ready tables via Amazon Athena. Orchestrated by AWS Step Functions, fully provisioned with Terraform, and deployed via GitHub Actions CI/CD.

---

## Documentation

| Doc | Description |
|---|---|
| [Architecture](docs/architecture.md) | System diagram, medallion layers, pipeline flow, AWS services |
| [Data Sources & Schemas](docs/data-sources-and-schemas.md) | Source CSV fields; Bronze, Silver, and Gold table schemas |
| [Glue Scripts](docs/glue-scripts.md) | Per-script breakdown of transformation logic |
| [Terraform Modules](docs/terraform-modules.md) | All 10 modules: VPC, KMS, storage, IAM, Glue, Step Functions, EventBridge, Lake Formation, Athena, monitoring |
| [Deployment](docs/deployment.md) | Prerequisites, step-by-step setup, configuration variables, teardown |
| [CI/CD](docs/cicd.md) | GitHub Actions workflow: lint, test, deploy |
| [Security](docs/security.md) | Encryption, network isolation, IAM, Lake Formation governance |
| [Monitoring & Cost](docs/monitoring.md) | CloudWatch dashboard, alarms, lifecycle policies, cost controls |
| [Athena Queries](docs/athena-queries.md) | Named queries for revenue, product performance, customer LTV, data quality |
| [Deliverables](docs/deliverables.md) | Requirements mapping from the project brief to the implementation |

---

## Quick Start

```bash
# 1. Bootstrap remote state
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket "ecom-lakehouse-tfstate-${ACCOUNT_ID}" --region us-east-1
aws dynamodb create-table --table-name ecom-lakehouse-tfstate-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# 2. Deploy infrastructure
cd terraform
terraform init -backend-config="bucket=ecom-lakehouse-tfstate-${ACCOUNT_ID}" \
               -backend-config="key=lakehouse/terraform.tfstate" \
               -backend-config="region=us-east-1"
terraform apply -var="aws_account_id=${ACCOUNT_ID}" -var="sns_alert_email=your@email.com"

# 3. Upload Glue scripts
aws s3 cp glue_scripts/ s3://ecom-lakehouse-glue-assets-${ACCOUNT_ID}/scripts/ --recursive

# 4. Drop data to trigger the pipeline
aws s3 cp data/ s3://ecom-lakehouse-raw-${ACCOUNT_ID}/uploads/ --recursive
```

See [Deployment](docs/deployment.md) for the full guide.

---

## Project Structure

```
AWSProject2/
├── docs/                        # Project documentation
├── terraform/
│   ├── main.tf                  # Root module
│   ├── backend.tf               # Remote state
│   ├── variables.tf
│   └── modules/                 # 10 infrastructure modules
└── glue_scripts/
    ├── utils/delta_utils.py     # Shared Delta Lake helpers
    ├── ingestion/               # raw_to_bronze
    ├── bronze_to_silver/        # products, orders, order_items
    └── silver_to_gold/          # daily_revenue, product_performance, customer_orders
```

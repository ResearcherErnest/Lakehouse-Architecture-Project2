# ── Remote State Backend ──────────────────────────────────────────────────────
# Run bootstrap/ first to create this bucket and DynamoDB table.
# Then update the values below with the outputs from bootstrap and run:
#   terraform init -backend-config=backend.tf

terraform {
  backend "s3" {
    bucket         = "ecom-lakehouse-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "ecom-lakehouse/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ecom-lakehouse-tfstate-locks"
    encrypt        = true
  }
}

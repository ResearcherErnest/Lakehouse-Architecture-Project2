# ── VPC ───────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── KMS ───────────────────────────────────────────────────────────────────────

module "kms" {
  source = "./modules/kms"

  project_name   = var.project_name
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
}

# ── Storage ───────────────────────────────────────────────────────────────────

module "storage" {
  source = "./modules/storage"

  project_name   = var.project_name
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  kms_key_arn    = module.kms.key_arn

  depends_on = [module.kms]
}

# ── IAM ───────────────────────────────────────────────────────────────────────

module "iam" {
  source = "./modules/iam"

  project_name           = var.project_name
  aws_account_id         = var.aws_account_id
  aws_region             = var.aws_region
  kms_key_arn            = module.kms.key_arn
  lakehouse_bucket_arn   = module.storage.lakehouse_bucket_arn
  raw_bucket_arn         = module.storage.raw_bucket_arn
  glue_assets_bucket_arn = module.storage.glue_assets_bucket_arn

  depends_on = [module.storage, module.kms]
}

# ── Lake Formation ────────────────────────────────────────────────────────────

module "lake_formation" {
  source = "./modules/lake_formation"

  project_name            = var.project_name
  aws_account_id          = var.aws_account_id
  lakehouse_bucket_arn    = module.storage.lakehouse_bucket_arn
  lake_formation_role_arn = module.iam.lake_formation_role_arn
  glue_execution_role_arn = module.iam.glue_execution_role_arn
  glue_crawler_role_arn   = module.iam.glue_crawler_role_arn
  bronze_database_name    = module.glue.bronze_database_name
  silver_database_name    = module.glue.silver_database_name
  gold_database_name      = module.glue.gold_database_name

  depends_on = [module.iam, module.glue]
}

# ── Glue ──────────────────────────────────────────────────────────────────────

module "glue" {
  source = "./modules/glue"

  project_name            = var.project_name
  aws_region              = var.aws_region
  aws_account_id          = var.aws_account_id
  glue_execution_role_arn = module.iam.glue_execution_role_arn
  glue_crawler_role_arn   = module.iam.glue_crawler_role_arn
  lakehouse_bucket_name   = module.storage.lakehouse_bucket_name
  glue_assets_bucket_name = module.storage.glue_assets_bucket_name
  raw_bucket_name         = module.storage.raw_bucket_name
  kms_key_arn             = module.kms.key_arn
  vpc_subnet_ids          = module.vpc.private_subnet_ids
  glue_security_group_id  = module.vpc.glue_security_group_id
  worker_type             = var.glue_worker_type
  num_workers             = var.glue_num_workers

  depends_on = [module.iam, module.storage, module.vpc, module.kms]
}

# ── Step Functions ────────────────────────────────────────────────────────────

module "step_functions" {
  source = "./modules/step_functions"

  project_name            = var.project_name
  aws_region              = var.aws_region
  aws_account_id          = var.aws_account_id
  step_functions_role_arn = module.iam.step_functions_role_arn
  glue_job_names          = module.glue.job_names
  glue_crawler_names      = module.glue.crawler_names
  sns_alert_email         = var.sns_alert_email
  kms_key_arn             = module.kms.key_arn

  depends_on = [module.glue, module.iam, module.kms]
}

# ── EventBridge ───────────────────────────────────────────────────────────────

module "eventbridge" {
  source = "./modules/eventbridge"

  project_name        = var.project_name
  aws_region          = var.aws_region
  aws_account_id      = var.aws_account_id
  state_machine_arn   = module.step_functions.state_machine_arn
  raw_bucket_name     = module.storage.raw_bucket_name
  schedule_expression = var.schedule_expression

  depends_on = [module.step_functions, module.storage]
}

# ── Athena ────────────────────────────────────────────────────────────────────

module "athena" {
  source = "./modules/athena"

  project_name               = var.project_name
  athena_results_bucket_name = module.storage.athena_results_bucket_name
  gold_database_name         = module.glue.gold_database_name
  silver_database_name       = module.glue.silver_database_name

  depends_on = [module.storage, module.glue]
}

# ── Monitoring ────────────────────────────────────────────────────────────────

module "monitoring" {
  source = "./modules/monitoring"

  project_name          = var.project_name
  aws_region            = var.aws_region
  aws_account_id        = var.aws_account_id
  glue_job_names = {
    raw_to_bronze            = "${var.project_name}-raw-to-bronze"
    products_silver          = "${var.project_name}-products-silver"
    orders_silver            = "${var.project_name}-orders-silver"
    order_items_silver       = "${var.project_name}-order-items-silver"
    daily_revenue_gold       = "${var.project_name}-daily-revenue-gold"
    product_performance_gold = "${var.project_name}-product-performance-gold"
    customer_orders_gold     = "${var.project_name}-customer-orders-gold"
  }
  state_machine_name    = module.step_functions.state_machine_name
  sns_topic_arn         = module.step_functions.sns_topic_arn
  lakehouse_bucket_name = module.storage.lakehouse_bucket_name
  monthly_budget_usd    = var.monthly_budget_usd
  budget_alert_email    = var.sns_alert_email
  log_retention_days    = var.log_retention_days

  depends_on = [module.step_functions, module.glue, module.storage]
}

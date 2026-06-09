# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpc" })
}

# ── Private subnets (one per AZ — Glue runs multi-AZ) ────────────────────────

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

# ── Security group for Glue jobs ──────────────────────────────────────────────
# Glue requires a self-referencing rule so executors can communicate with each other.

resource "aws_security_group" "glue" {
  name        = "${var.project_name}-glue-sg"
  description = "Security group for AWS Glue jobs — self-referencing egress only"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.project_name}-glue-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "glue_self" {
  security_group_id            = aws_security_group.glue.id
  referenced_security_group_id = aws_security_group.glue.id
  ip_protocol                  = "-1"
  description                  = "Allow all traffic from within the same security group (Glue executor comms)"
}

resource "aws_vpc_security_group_egress_rule" "glue_self" {
  security_group_id            = aws_security_group.glue.id
  referenced_security_group_id = aws_security_group.glue.id
  ip_protocol                  = "-1"
  description                  = "Allow all egress to same security group"
}

resource "aws_vpc_security_group_egress_rule" "glue_https" {
  security_group_id = aws_security_group.glue.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow HTTPS egress to VPC endpoints (S3, Glue, KMS, CWL)"
}

# ── VPC Endpoints ─────────────────────────────────────────────────────────────

# S3 Gateway endpoint — free, routes S3 traffic over AWS backbone
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.project_name}-vpce-s3" })
}

# Glue Interface endpoint — control-plane calls from private subnets
resource "aws_vpc_endpoint" "glue" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.glue"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.glue.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpce-glue" })
}

# KMS Interface endpoint — encryption operations stay in-VPC
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.glue.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpce-kms" })
}

# CloudWatch Logs Interface endpoint — log shipping without internet
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.glue.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpce-cwlogs" })
}

# Step Functions Interface endpoint — SF API calls from Glue/Lambda
resource "aws_vpc_endpoint" "step_functions" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.states"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.glue.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpce-sfn" })
}

# ── Route table for private subnets ──────────────────────────────────────────

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.project_name}-rt-private" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_region" "current" {}

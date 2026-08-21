locals {
  name = "bedrock-data"
}

# -----------------------------------------------------------------------------
# Security Group for Databases
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "Security group for RDS instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

# -----------------------------------------------------------------------------
# Catalog Database (MySQL)
# -----------------------------------------------------------------------------
resource "random_password" "catalog_db" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "catalog_db" {
  name                    = "${local.name}-catalog-db-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "catalog_db" {
  secret_id = aws_secretsmanager_secret.catalog_db.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.catalog_db.result
  })
}

resource "aws_db_instance" "catalog" {
  identifier              = "${local.name}-catalog"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  db_name                 = "catalog"
  username                = "admin"
  password                = random_password.catalog_db.result
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  skip_final_snapshot     = true
  backup_retention_period = var.backup_retention_days
}

# -----------------------------------------------------------------------------
# Orders Database (PostgreSQL)
# -----------------------------------------------------------------------------
resource "random_password" "orders_db" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "orders_db" {
  name                    = "${local.name}-orders-db-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.orders_db.result
  })
}

resource "aws_db_instance" "orders" {
  identifier              = "${local.name}-orders"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  db_name                 = "orders"
  username                = "dbadmin"
  password                = random_password.orders_db.result
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  skip_final_snapshot     = true
  backup_retention_period = var.backup_retention_days
}

# -----------------------------------------------------------------------------
# Carts Database (DynamoDB)
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "carts" {
  name         = "retail-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # The carts service queries carts by customer via this GSI — confirmed
  # from the app's own runtime error ("The table does not have the
  # specified index: idx_global_customerId") once persistence config was
  # otherwise correct. Without it, add-to-cart / view-cart lookups fail
  # even though basic PutItem/GetItem by id would work.
  attribute {
    name = "customerId"
    type = "S"
  }

  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }
}

output "catalog_db_endpoint" {
  value = aws_db_instance.catalog.endpoint
}

output "orders_db_endpoint" {
  value = aws_db_instance.orders.endpoint
}

output "carts_dynamodb_table" {
  value = aws_dynamodb_table.carts.name
}

output "catalog_secret_name" {
  value = aws_secretsmanager_secret.catalog_db.name
}

output "orders_secret_name" {
  value = aws_secretsmanager_secret.orders_db.name
}

output "carts_dynamodb_arn" {
  value = aws_dynamodb_table.carts.arn
}

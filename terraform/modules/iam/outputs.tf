output "dev_access_key_id" {
  value = aws_iam_access_key.dev.id
}
output "dev_secret_access_key" {
  value     = aws_iam_access_key.dev.secret
  sensitive = true
}
output "dev_console_password" {
  value     = aws_iam_user_login_profile.dev.password
  sensitive = true
}
output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}
output "carts_irsa_role_arn" {
  value = module.carts_irsa.iam_role_arn
}
output "eso_irsa_role_arn" {
  value = module.eso_irsa.iam_role_arn
}

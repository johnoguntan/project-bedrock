# Partial backend configuration.
#
# The bucket name isn't hardcoded here on purpose — it's supplied at
# `terraform init` time via backend.hcl (see backend.hcl.example in this
# same directory). This keeps the bucket name out of version-controlled
# .tf files, though for THIS project it isn't secret — you can also just
# hardcode it below if you prefer one less moving part.
#
# use_lockfile = true is Terraform 1.11+'s native S3 state locking.
# No DynamoDB table is created or required — per the exam brief, that's
# optional and we're skipping it.

terraform {
  backend "s3" {
    bucket       = "bedrock-tfstate-alt-soe-tin-025-0379"
    key          = "project-bedrock/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

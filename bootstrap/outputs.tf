output "state_bucket_name" {
  description = "S3 bucket name — use as the `bucket` value in every environment's backend.tf for this account."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name — use as the `dynamodb_table` value in every environment's backend.tf for this account."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config_snippet" {
  description = "Copy directly into the corresponding environment's backend.tf (with the correct `key` for that component — see docs/bootstrap-guide.md)."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
        encrypt        = true
        # key = "<environment>/<component>/terraform.tfstate"  <- set per environments/*/backend.tf
      }
    }
  EOT
}

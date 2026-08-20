terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<production-account-id>"
    key            = "production/platform/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

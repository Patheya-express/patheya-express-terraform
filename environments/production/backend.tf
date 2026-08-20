terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<production-account-id>"
    key            = "production/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

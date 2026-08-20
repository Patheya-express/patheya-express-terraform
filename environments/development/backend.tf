terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<development-account-id>"
    key            = "development/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

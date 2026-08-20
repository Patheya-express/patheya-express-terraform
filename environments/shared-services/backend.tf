terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<shared-services-account-id>"
    key            = "shared-services/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

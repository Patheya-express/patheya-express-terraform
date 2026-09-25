terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-512297269884"
    key            = "production/platform/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

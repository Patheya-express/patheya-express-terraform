terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-668506406019"
    key            = "shared-services/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-596090776380"
    key            = "qa/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

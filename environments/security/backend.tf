terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-512206886196"
    key            = "security/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

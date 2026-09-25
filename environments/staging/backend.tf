terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-214920155808"
    key            = "staging/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<staging-account-id>"
    key            = "staging/cluster/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

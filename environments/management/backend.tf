# Values come from bootstrap/'s output for the management account — run bootstrap there first
# (docs/bootstrap-guide.md), then fill these in. Left as literal values, not variables — a
# backend block cannot reference input variables or locals (Terraform limitation, not a choice).
terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-<management-account-id>"
    key            = "management/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}

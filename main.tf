provider "aws" {
  region = local.region
}

locals {
  name   = "homework"
  region = "ap-southeast-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  domain_prefix = var.domain_prefix
  zone_id       = var.zone_id
  zone_name     = var.zone_name
}
variable "domain_prefix" {
  description = "The first segment of the domain"
  type        = string
}

variable "zone_id" {
  description = "The ID of the hosted zone"
  type        = string
}

variable "zone_name" {
  description = "The name of the hosted zone"
  type        = string
}
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type = map(string)
  default = {
    public_services = "10.0.0.0/24"
    ui_public       = "10.0.1.0/24"
  }
}

variable "private_subnets" {
  type = map(string)
  default = {
    service_subnet = "10.0.10.0/24"
    db_private     = "10.0.11.0/24"
  }
}

variable "key_pair_name" {
  type    = string
  default = "prof1"
}

variable "db_username" {
  type        = string
  default     = "vectoradmin"
  description = "RDS master username"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password"
}

variable "portkey_api_key" {
  type        = string
  sensitive   = true
  description = "API Key for Portkey AI"

}

variable "openai_api_key" {
  description = "OpenAI API key for LLM"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string

}

variable "ami_id" {
  description = "amazon linux 2023 AMI ID"
  type        = string

}

variable "aws_default_vpc" {
  type    = string
  default = "default"
}

variable "key_name" {
  type        = string
  description = "name of existing aws keypair"
  default     = "server_key"

}






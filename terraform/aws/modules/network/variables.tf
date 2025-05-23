variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidr_1" {
  type        = string
  description = "CIDR block for the first public subnet"
}

variable "public_subnet_cidr_2" {
  type        = string
  description = "CIDR block for the second public subnet"
}

variable "availability_zone_1" {
  type        = string
  description = "Availability zone for the first public subnet"
}

variable "availability_zone_2" {
  type        = string
  description = "Availability zone for the second public subnet"
}

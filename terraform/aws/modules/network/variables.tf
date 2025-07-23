variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the main VPC"
  default     = "10.10.0.0/16" # Your actual primary VPC CIDR
}

variable "secondary_vpc_cidr" {
  type        = string
  description = "Secondary CIDR block to associate with the VPC for additional address space"
  default     = "10.11.0.0/16"
}

variable "public_subnet_cidr_1" {
  type        = string
  description = "CIDR block for the first public subnet (from primary VPC CIDR)"
  default     = "10.10.1.0/24" # Your actual existing public subnet 1
}

variable "public_subnet_cidr_2" {
  type        = string
  description = "CIDR block for the second public subnet (from primary VPC CIDR)"
  default     = "10.10.2.0/24" # Your actual existing public subnet 2
}

variable "public_subnet_cidr_3" {
  type        = string
  description = "CIDR block for the third public subnet (from secondary VPC CIDR)"
  default     = "10.11.0.0/20" # Your new larger public subnet 3
}

variable "public_subnet_cidr_4" {
  type        = string
  description = "CIDR block for the fourth public subnet (from secondary VPC CIDR)"
  default     = "10.11.16.0/20" # Your new larger public subnet 4
}

variable "availability_zone_1" {
  type        = string
  description = "Availability zone for the first and third public subnets"
  default     = "ap-south-1a"
}

variable "availability_zone_2" {
  type        = string
  description = "Availability zone for the second and fourth public subnets"
  default     = "ap-south-1b"
}


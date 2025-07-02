variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the EKS cluster"
}

variable "cluster_role_name" {
  type        = string
  description = "Name of the IAM role for the EKS cluster"
}

variable "node_role_name" {
  type        = string
  description = "Name of the IAM role for the EKS worker nodes"
}

variable "instance_type" {
  type        = string
  description = "Instance type for the EKS worker nodes"
  default     = "t2.large" # Previous c6a.8xlarge
}

variable "desired_size" {
  type        = number
  description = "Desired number of worker nodes"
  default     = 1 # Default desired size, can be overridden
}


variable "max_size" {
  type        = number
  description = "Maximum number of worker nodes"
  default     =  1 # Default maximum size, can be overridden
}

variable "min_size" {
  type        = number
  description = "Minimum number of worker nodes"
  default     = 1 # Default minimum size, can be overridden
}

variable "disk_size" {
  type        = number
  description = "Disk size in GiB for the EKS worker nodes root volume."
  default     = 1024 
}

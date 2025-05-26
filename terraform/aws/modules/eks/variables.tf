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
}

variable "desired_size" {
  type        = number
  description = "Desired number of worker nodes"
}

variable "max_size" {
  type        = number
  description = "Maximum number of worker nodes"
}

variable "min_size" {
  type        = number
  description = "Minimum number of worker nodes"
}

variable "enable_ebs_csi_driver" {
  description = "Whether to enable the AWS EBS CSI driver EKS add-on."
  type        = bool
  default     = false # Set to false by default, you'll set it to true in terragrunt
}

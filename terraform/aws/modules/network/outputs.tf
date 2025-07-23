output "vpc_id" {
  value       = aws_vpc.eks_vpc.id
  description = "ID of the VPC"
}

output "public_subnet_ids" {
  value       = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id,
    aws_subnet.public_subnet_3.id, # Added the new subnet 3 ID
    aws_subnet.public_subnet_4.id  # Added the new subnet 4 ID
  ]
  description = "List of IDs of all public subnets"
}

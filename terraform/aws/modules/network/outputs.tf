output "vpc_id" {
  value       = aws_vpc.eks_vpc.id
  description = "ID of the VPC"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  description = "List of IDs of the public subnets"
}

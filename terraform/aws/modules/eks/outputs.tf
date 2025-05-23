output "eks_cluster_id" {
  value       = aws_eks_cluster.eks.id
  description = "ID of the EKS cluster"
}

output "eks_node_group_name" {
  value       = aws_eks_node_group.eks_nodes.id
  description = "Name of the EKS node group"
}

output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.eks.endpoint
  description = "Endpoint of the EKS cluster"
}

output "eks_cluster_kubeconfig" {
  value       = aws_eks_cluster.eks.kubeconfig[0].cluster_ca_certificate_authority_data
  description = "Base64 encoded certificate data for cluster access"
  sensitive   = true
}

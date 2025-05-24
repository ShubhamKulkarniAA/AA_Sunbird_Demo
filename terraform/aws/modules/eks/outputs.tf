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
  value = {
    endpoint                    = aws_eks_cluster.eks.endpoint
    cluster_ca_certificate_data = aws_eks_cluster.eks.certificate_authority[0].data
    cluster_name                = aws_eks_cluster.eks.name
  }
  description = "EKS cluster kubeconfig info"
  sensitive   = true
}

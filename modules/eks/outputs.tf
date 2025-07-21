output "cluster_name" {
    value = var.cluster_name
}

output "vpc_id" {
    value = aws_vpc.vpc.id
}

output "public_subnet_ids" {
    value = aws_subnet.sn_pub[*].id
}

output "private_subnet_ids" {
    value = aws_subnet.sn_private[*].id
}

output "nat_gateway_id" {
    value = aws_nat_gateway.nat.id
}

output "internet_gateway_id" {
    value = aws_internet_gateway.ig.id
}

output "security_group_id" {
    value = aws_security_group.sg.id
}

output "eip_id" {
    value = aws_eip.ip.id
}

output "route_table_public_id" {
    value = aws_route_table.public_rt.id
}

output "route_table_private_id" {
    value = aws_route_table.private_rt.id
}

output "cluster_id" {
    value = aws_eks_cluster.eks.id
}

output "cluster_endpoint" {
    value = aws_eks_cluster.eks.endpoint
}
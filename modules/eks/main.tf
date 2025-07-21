resource "aws_vpc" "vpc" {
    cidr_block              = var.cidr_block
    region                  = var.region
    enable_dns_hostnames    = var.enable_dns_hostnames
    enable_dns_support      = var.enable_dns_support
    tags                    = {
        name = var.vpc_name
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
}

resource "aws_subnet" "sn_pub" {
    count                   = length(var.public_subnet_cidrs)
    region                  = var.region
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = var.public_subnet_cidrs[count.index]
    availability_zone       = var.azs[count.index]
    map_public_ip_on_launch = true

    tags                    = {
        name = "${var.vpc_name}-publicsn"
        "kubernetes.io/role/elb" = "1"
    }
}

resource "aws_subnet" "sn_private" {
    count                   = length(var.private_subnet_cidrs) 
    region                  = var.region
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = var.private_subnet_cidrs[count.index]
    availability_zone       = var.azs[count.index]

    tags                    = {
        name = "${var.vpc_name}-privatesn"
        "kubernetes.io/role/internal-elb" = "1"
    }
}

resource "aws_internet_gateway" "ig" {
    vpc_id = aws_vpc.vpc.id
    tags = {
        name = "${var.vpc_name}-ig"
    }
}

resource "aws_eip" "ip" {
    domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.ip.id
    subnet_id     = aws_subnet.sn_pub[0].id

    tags = {
        name = "${var.vpc_name}-nat"
    }
}

resource "aws_route_table" "public_rt" {
    vpc_id         = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.ig.id
    }
    tags = {
        name = "${var.vpc_name}-public-rt"
    }
}

resource "aws_route_table_association" "public_assoc" {
    count           = length(aws_subnet.sn_pub) 
    subnet_id       = aws_subnet.sn_pub[count.index].id
    route_table_id  = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
    vpc_id         = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.nat.id
    }
    tags = {
        name = "${var.vpc_name}-private-rt"
    }
}

resource "aws_route_table_association" "private_assoc" {
    count           = length(aws_subnet.sn_private)
    subnet_id       = aws_subnet.sn_private[count.index].id
    route_table_id  = aws_route_table.private_rt.id
}

resource "aws_security_group" "sg" {
    name        = "${var.vpc_name}-sg"
    vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "sg_ingress" {
    for_each          = toset(var.cidr_block_sg)
    security_group_id = aws_security_group.sg.id
    ip_protocol       = "-1"   
    cidr_ipv4         = each.key
}

resource "aws_vpc_security_group_egress_rule" "sg_egress" {
    security_group_id = aws_security_group.sg.id
    ip_protocol       = "-1"
    cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "eks" {
    name = var.cluster_name
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "eks.amazonaws.com"
                }
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "eks" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role = aws_iam_role.eks.name
}

resource "aws_eks_cluster" "eks" {
    name = var.cluster_name
    role_arn = aws_iam_role.eks.arn
    access_config {
      authentication_mode = "API"
    }
    vpc_config {
        subnet_ids = aws_subnet.sn_private[*].id
        security_group_ids = [aws_security_group.sg.id]
    }
    depends_on = [
        aws_iam_role_policy_attachment.eks,
        aws_internet_gateway.ig,
        aws_nat_gateway.nat,
        aws_route_table_association.public_assoc,
        aws_route_table_association.private_assoc
    ]
    tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
}

resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "ng" {
    cluster_name    = aws_eks_cluster.eks.name
    node_group_name = "${var.cluster_name}-ng"
    node_role_arn   = aws_iam_role.node_group.arn
    subnet_ids      = aws_subnet.sn_private[*].id
    instance_types  = ["t3.medium"]

    scaling_config {
        desired_size = 2
        max_size     = 3
        min_size     = 1
    }

    depends_on = [
        aws_eks_cluster.eks,
        aws_vpc_security_group_ingress_rule.sg_ingress,
        aws_vpc_security_group_egress_rule.sg_egress
    ]
}
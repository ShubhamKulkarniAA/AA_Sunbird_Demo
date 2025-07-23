resource "aws_vpc" "eks_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "terraform-eks-vpc" }
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = var.secondary_vpc_cidr
}

# Public subnets in primary CIDR
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.public_subnet_cidr_1
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_1
  tags                    = { Name = "terraform-eks-public-subnet-1" }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.public_subnet_cidr_2
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_2
  tags                    = { Name = "terraform-eks-public-subnet-2" }
}

# Public subnets in secondary CIDR
resource "aws_subnet" "public_subnet_3" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.public_subnet_cidr_3
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_1
  tags                    = { Name = "terraform-eks-public-subnet-3" }
  depends_on              = [aws_vpc_ipv4_cidr_block_association.secondary_cidr]
}

resource "aws_subnet" "public_subnet_4" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.public_subnet_cidr_4
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_2
  tags                    = { Name = "terraform-eks-public-subnet-4" }
  depends_on              = [aws_vpc_ipv4_cidr_block_association.secondary_cidr]
}

# Internet Gateway and Route Table
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "terraform-eks-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "terraform-eks-public-rt" }
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Route table associations for all 4 subnets
resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_3_assoc" {
  subnet_id      = aws_subnet.public_subnet_3.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_4_assoc" {
  subnet_id      = aws_subnet.public_subnet_4.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_eks_cluster" "eks" {
  name     = "demo-sunbirdedAA-eks"
  role_arn = "arn:aws:iam::339712817291:role/sunbirdedAA-demo-EKSClusterRole"  

  vpc_config {
    subnet_ids = [
      aws_subnet.public_subnet_1.id,
      aws_subnet.public_subnet_2.id,
      aws_subnet.public_subnet_3.id,
      aws_subnet.public_subnet_4.id
    ]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  version = "1.32"  
  

}



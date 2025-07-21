terraform {
  required_providers {
    aws = {
        source   = "hashicorp/aws"
        version  = "6.4.0"
    }
    local = {
        source   = "hashicorp/local"
        version  = "2.5.3"
    }
    random = {
        source   = "hashicorp/random"
        version  = "3.4.3"
    }
  }
}

provider "aws" {
    region = "ap-south-1"
}
provider "local" {

}

provider "random" {

}

resource "random_string" "name_suffix" {
    length  = 6
    special = false
}

locals {
    cluster_name = "sai-eks-cluster-${random_string.name_suffix.result}"
}

data "aws_availability_zones" "azs" {
  
}

module "eks" {
    cluster_name = local.cluster_name
    source = "./modules/eks"
    vpc_name = "sai-eks-vpc-${random_string.name_suffix.result}"
    cidr_block = "10.0.0.0/16"
    region = "ap-south-1"
    cidr_block_sg = [
    "10.0.0.0/18",
    "192.168.0.0/16",
    "172.16.0.0/12",
    ]
    enable_dns_hostnames = true
    enable_dns_support = true
    public_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24"]
    private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
    azs = data.aws_availability_zones.azs.names
}
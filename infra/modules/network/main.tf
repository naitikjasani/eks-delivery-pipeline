# main.tf: the network for the cluster. One VPC, 2 public subnets, an internet gateway and one route table.
#
# WHY PUBLIC SUBNETS AND NO NAT GATEWAY? Cost.
# The textbook setup puts nodes in PRIVATE subnets and gives them internet access (to pull images, reach the EKS API)
# through a NAT gateway. A NAT gateway costs ~$0.056/hour plus data charges, more than both of our Spot nodes together.
# Instead, nodes sit in public subnets and get their own public IPs, so they reach the internet directly through
# the free internet gateway.
# Is that safe enough for a demo? The EKS-managed cluster security group only allows traffic from inside the
# cluster, so nothing on the internet can connect to the nodes, even though they have public IPs.
# In production you'd use private subnets + a NAT gateway (or VPC endpoints) for defence in depth.

# The Availability Zones (separate data centres) in this region that are currently usable.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # EKS requires subnets in at least 2 AZs. We use the first two, which also means the cluster
  # survives if one data centre has problems.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both are required by EKS: nodes must resolve DNS names (e.g. the cluster API endpoint)
  # and get DNS hostnames, otherwise they can't register with the cluster.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_subnet" "public" {
  # One subnet per AZ (count.index = 0 and 1).
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  # cidrsubnet("10.0.0.0/16", 4, i) adds 4 bits to the prefix → /20 subnets (4,096 addresses each):
  # 10.0.0.0/20 and 10.0.16.0/20. Each pod gets a VPC IP (AWS VPC CNI), so a roomy subnet helps.
  cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index)

  # Instances launched here get a public IP automatically. Without a NAT gateway, that's how nodes reach the internet.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${local.azs[count.index]}"
    # Tells Kubernetes this subnet may be used for internet-facing load balancers. We never create one
    # (no Service type LoadBalancer), but it's the standard tag and harmless.
    "kubernetes.io/role/elb" = "1"
    # Marks the subnet as usable by this cluster. "shared" = other clusters may use it too.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# The VPC's door to the internet. Free (unlike a NAT gateway); you pay only for data transfer.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# Routing rules for the public subnets.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  # Any traffic not addressed to the VPC itself (0.0.0.0/0 = "everything else") goes out via the internet gateway.
  # This route is what makes these subnets "public".
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# Attach the route table to both subnets. Without this they'd use the VPC's main route table (no internet).
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

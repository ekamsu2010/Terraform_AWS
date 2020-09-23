provider "aws" {
  access_key = "Your Access Key here"
  secret_key = "Your Secret Access Key "
  region     = "us-east-1"
}

# Create VPC
resource "aws_vpc" "dev_vpc" {
  cidr_block            = "10.0.0.0/16"
  instance_tenancy      = "default"
  enable_dns_hostnames  = true
  tags = {
    Name = "Dev"
  }
}

# Launch Internet Gateway in the VPC
resource "aws_internet_gateway" "Dev_igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "Dev_igw"
  }
}


# Create first subnet
resource "aws_subnet" "Pub_subnet" {
  vpc_id                    = aws_vpc.dev_vpc.id
  cidr_block                = "10.0.1.0/24"
  availability_zone         = "us-east-1a"
  map_public_ip_on_launch   = true
  depends_on                = [aws_internet_gateway.Dev_igw]

  tags = {
    Name = "Dev_Pub_Subnet"
  }
}

# Create second subnet
resource "aws_subnet" "Priv_subnet" {
  vpc_id                    = aws_vpc.dev_vpc.id
  cidr_block                = "10.0.2.0/24"
  availability_zone         = "us-east-1b"
  map_public_ip_on_launch   = false
  
  tags = {
    Name = "Dev_Priv_Subnet"
  }
}

resource "aws_eip" "Dev_nat_eip" {
  vpc           = true
  depends_on    = [aws_internet_gateway.Dev_igw]
}

# Launch NAT Gateway in public subnet
resource "aws_nat_gateway" "Dev_natgw" {
  allocation_id = aws_eip.Dev_nat_eip.id
  subnet_id     = aws_subnet.Pub_subnet.id
  depends_on    = [aws_internet_gateway.Dev_igw]
  
  tags = {
    Name = "Dev_NAT"
  }
}

# Setup NACL
# We will keep the default ACL created with the VPC and it's rules

# Setup route tables_ Main and Custom
resource "aws_default_route_table" "Dev_default_rt" {
  default_route_table_id = aws_vpc.dev_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.Dev_natgw.id
  }

  tags = {
    Name = "Dev_Default_RT"
  }
}

resource "aws_route_table" "custom_rt" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Dev_igw.id
  }

  tags = {
    Name = "Dev_custom_RT"
  }
}

# Associate subnets to route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.Pub_subnet.id
  route_table_id = aws_route_table.custom_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id         = aws_subnet.Priv_subnet.id
  route_table_id    = aws_default_route_table.Dev_default_rt.id
}

# Setup Security Groups
resource "aws_security_group" "Dev_Web_SG" {
  name        = "Web_Tier_Traffic"
  description = "Allow TLS, ssh and HTTP inbound traffic"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Dev_Web_SG"
  }
}

resource "aws_security_group" "Dev_DB_SG" {
  name        = "DB_Traffic"
  description = "Allow ssh inbound traffic from web_SG"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "SSH from Web Tier"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    security_groups = [aws_security_group.Dev_Web_SG.id]
  }

  ingress {
    description = "icmp from VPC"
    from_port   = 23
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Dev_DB_SG"
  }
}

# Launch 1st instance (t2.micro instance with free linux AMI)
resource "aws_instance" "Web_Instance" {
  ami               = "ami-0c94855ba95c71c99"
  instance_type     = "t2.micro"
  key_name          = "TerraKP"

  subnet_id         = aws_subnet.Pub_subnet.id
  security_groups = [aws_security_group.Dev_Web_SG.id]
  depends_on        = [aws_internet_gateway.Dev_igw]

  tags = {
      Name = "Dev_Pub_Web_Instance"
  }
}

# Launch Bastion host in public subnet (t2.micro instance with linux AMI)
resource "aws_instance" "Bastion_Instance" {
  ami               = "ami-0c94855ba95c71c99"
  instance_type     = "t2.micro"
  key_name          = "TerraKP"

  subnet_id         = aws_subnet.Pub_subnet.id
  security_groups = [aws_security_group.Dev_Web_SG.id]
  depends_on        = [aws_internet_gateway.Dev_igw]

  tags = {
      Name = "Dev_Bastion_Instance"
  }
}

# Launch DB instance in private subnet (t2.micro instance with free linux AMI)
resource "aws_instance" "DB_Instance" {
  ami                = "ami-0c94855ba95c71c99"
  instance_type      = "t2.micro"
  key_name           = "TerraKP"

  subnet_id          = aws_subnet.Priv_subnet.id
  security_groups    = [aws_security_group.Dev_DB_SG.id]

  tags = {
      Name = "Dev_Priv_DB_Instance"
  }
}
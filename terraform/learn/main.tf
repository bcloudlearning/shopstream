resource "aws_s3_bucket" "learn" {
  bucket = "shopstream-learn-cloudexpert2026"
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
}


resource "aws_instance" "learn" {
  ami               = data.aws_ami.al2023_arm.id
  instance_type     = var.instance_type
  availability_zone = "ap-south-2a"

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "shopstream-learn-ec2-v2"
  }
}
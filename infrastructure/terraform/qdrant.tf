# Data source for Ubuntu 22.04 AMI
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Network interface with static IP for Qdrant
resource "aws_network_interface" "qdrant" {
  subnet_id       = aws_subnet.private["db_private"].id
  private_ips     = ["10.0.11.10"] # Static IP
  security_groups = [aws_security_group.qdrant.id]

  tags = {
    Name = "qdrant-eni"
  }
}

# Qdrant EC2 instance
resource "aws_instance" "qdrant" {
  ami           = data.aws_ami.ubuntu_2204.id
  instance_type = "t3.small"
  key_name      = var.key_pair_name

  network_interface {
    network_interface_id = aws_network_interface.qdrant.id
    device_index         = 0
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    
    # Log everything
    exec > >(tee /var/log/user-data.log)
    exec 2>&1
    
    echo "Starting Qdrant installation..."
    
    # Wait for network
    until ping -c1 google.com &>/dev/null; do
      sleep 5
    done
    
    # Update system
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    
    # Install Docker
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    
    # Create directory
    mkdir -p /var/lib/qdrant/storage
    
    # Run Qdrant
    docker run -d \
      --name qdrant \
      --restart unless-stopped \
      -p 6333:6333 \
      -p 6334:6334 \
      -v /var/lib/qdrant/storage:/qdrant/storage \
      qdrant/qdrant:latest
    
    echo "Qdrant ready at 10.0.11.10:6333" >> /etc/motd
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "qdrant-vector-db"
    Role = "vector-database"
  }
}
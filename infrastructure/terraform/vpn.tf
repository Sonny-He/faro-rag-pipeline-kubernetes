# EC2 instance that will act as OpenVPN server / bastion
resource "aws_instance" "vpn_server" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public["public_services"].id
  vpc_security_group_ids      = [aws_security_group.vpn.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  source_dest_check           = false
  user_data_replace_on_change = true

  tags = {
    Name = "vpn-server"
    Role = "vpn-bastion"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eux

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y wget curl ipcalc

    # Get and run Nyr's OpenVPN installer (non-interactive)
    wget https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O /root/openvpn-install.sh
    chmod +x /root/openvpn-install.sh

    PUBIP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo 127.0.0.1)

    AUTO_INSTALL=y \
    APPROVE_INSTALL=y \
    APPROVE_IP="$PUBIP" \
    APPROVE_DNS=1 \
    ENDPOINT="$PUBIP" \
    CLIENT="client1" \
    bash /root/openvpn-install.sh

    # Push VPC routes so VPN clients can reach your private subnets
    # (current private CIDRs: 10.0.10.0/24 = service_subnet, 10.0.11.0/24 = db_private)
    echo 'push "route 10.0.10.0 255.255.255.0"' >> /etc/openvpn/server/server.conf
    echo 'push "route 10.0.11.0 255.255.255.0"' >> /etc/openvpn/server/server.conf

    systemctl restart openvpn-server@server || systemctl restart openvpn@server

    # Put a copy of the client profile where you can scp it easily
    # Nyr writes /root/client.ovpn by default
    cp /root/client.ovpn /home/ubuntu/client.ovpn
    chown ubuntu:ubuntu /home/ubuntu/client.ovpn
    chmod 600 /home/ubuntu/client.ovpn

    echo "OpenVPN ready. Client: /home/ubuntu/client.ovpn" >> /etc/motd
  EOT
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
  owners = ["amazon"]
}


data "aws_vpc" "default" {
  default = true
}

resource "aws_key_pair" "ha-tunneling" {
  key_name   = "ha-tunneling-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "bastion_host_security_group" {

  description = "Enable SSH access to the host from external via SSH port"
  name        = "allow-ssh"
  vpc_id      = data.aws_vpc.default.id

}

resource "aws_security_group_rule" "ingress_ssh_host" {

  description = "Incoming traffic to bastion"
  type        = "ingress"
  from_port   = "22"
  to_port     = "22"
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}

resource "aws_security_group_rule" "ingress_http" {

  description = "HTTP traffic to bastion"
  type        = "ingress"
  from_port   = "80"
  to_port     = "80"
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}

resource "aws_security_group_rule" "ingress_https" {

  description = "HTTPS traffic to bastion"
  type        = "ingress"
  from_port   = "443"
  to_port     = "443"
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}

resource "aws_security_group_rule" "egress_host" {
  description = "Outgoing traffic from bastion to instances"
  type        = "egress"
  from_port   = "0"
  to_port     = "65535"
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}


data "template_file" "nginx_config" {
  template = file("${path.module}/template/nginx.config.tpl")
  vars = {
    SUBDOMAIN = "${var.subdomain}.duckdns.org"
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.ha-tunneling.key_name
  security_groups = [aws_security_group.bastion_host_security_group.name]
  user_data = <<-REALEND
                    #!/bin/bash
                    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
                    echo 'Installing nginx..'
                    sudo yum update -y
                    sudo amazon-linux-extras install nginx1 -y
                    sudo service nginx start

                    echo 'Installing certbot'
                    sudo amazon-linux-extras install epel -y
                    sudo yum install certbot-nginx -y

                    echo 'Setting IP for subdomain'
                    #PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
                    PUBLIC_IP=${aws_eip.lb.public_ip}
                    echo 'Public IP is '$PUBLIC_IP
                    echo 'URL: https://www.duckdns.org/update/${var.subdomain}/${var.duckdns_token}/'$PUBLIC_IP
                    curl --location --request GET 'https://www.duckdns.org/update/${var.subdomain}/${var.duckdns_token}/'$PUBLIC_IP
                    echo 'Installing certificate'
                    cat << EOF > /tmp/nginx.conf
                    ${data.template_file.nginx_config.rendered}
                    EOF
                    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bkp
                    sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf
                    sudo certbot --nginx -m ${var.email} -d ${var.subdomain}.duckdns.org --agree-tos -n
                REALEND

  tags = {
    Name = "proxy-home-assistant"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.lb.id
}

resource "aws_eip" "lb" {
  vpc      = true
}
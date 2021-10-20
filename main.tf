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

resource "aws_security_group_rule" "egress_host" {
  description = "Outgoing traffic from bastion to instances"
  type        = "egress"
  from_port   = "0"
  to_port     = "65535"
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}


resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.ha-tunneling.key_name
  security_groups = [aws_security_group.bastion_host_security_group.name]
  user_data = <<-EOF
                    #!/bin/bash
                    sudo yum update -y
                    sudo yum install nginx -y
                    sudo service nginx start
                EOF

  tags = {
    Name = "HelloWorld"
  }
}
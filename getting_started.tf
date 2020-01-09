variable "students" {
  type = list(object({
    login              = string,
    password           = object({ plaintext = string, hash = string }),
    variables          = object({
      follow_me_filename = string,
      super_secret       = string
    })
  }))
  description = "list of players"
}

variable "aws_access_key_id" {
  type = string
}
variable "aws_secret_access_key" {
  type = string
}
variable "aws_region" {
  type = string
}

variable "scenario_id" {
  type        = string
  description = "identifier for instance of this scenario"
}

locals {
  common_tags = {
    scenario_id = var.scenario_id
  }
}

provider "local" {
  version    = "~> 1"
}

provider "template" {
  version = "~> 2"
}

provider "tls" {
  version = "~> 2"
}

provider "aws" {
  version    = "~> 2"
  profile    = "default"
  region     = var.aws_region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


# create ssh key pair
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# save the private key locally for debugging
resource "local_file" "id_rsa" {
  sensitive_content  = tls_private_key.key.private_key_pem
  filename           = "${path.cwd}/id_rsa"
  provisioner "local-exec" {
    command = "chmod 600 ${path.cwd}/id_rsa"
  }
}

# upload the public key to aws
resource "aws_key_pair" "key" {
  key_name   = "getting_started (${var.scenario_id})"
  public_key = tls_private_key.key.public_key_openssh
}

data "template_cloudinit_config" "getting_started" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "bash_history.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/bash_history.yml.tpl", {
      aws_key_id  = var.aws_access_key_id
      aws_sec_key = var.aws_secret_access_key
      scenario_id = var.scenario_id
      players     = var.students
    })
  }

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/cloud-init.yml.tpl", {
      players = var.students
    })
  }
}

resource "aws_vpc" "cloud" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "getting_started/cloud"
    scenario_id = var.scenario_id
  }
}

resource "aws_internet_gateway" "default"{
  vpc_id = aws_vpc.cloud.id
}

resource "aws_subnet" "public" {
  vpc_id        = aws_vpc.cloud.id
  cidr_block    = "10.0.0.0/24"
  tags = {
    Name = "getting_started/public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cloud.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

}

resource "aws_route_table_association" "gs_subnet_route_table_association"{
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "getting_started" {
  vpc_id = aws_vpc.cloud.id
  name = "getting_started/${var.scenario_id}"

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_instance" "getting_started" {
  ami                    	= data.aws_ami.ubuntu.id
  instance_type          	= "t2.small"
  private_ip             	= "10.0.0.5"
  associate_public_ip_address   = true
  source_dest_check      	= false
  user_data_base64       	= data.template_cloudinit_config.getting_started.rendered
  subnet_id			= aws_subnet.public.id
  key_name               	= aws_key_pair.key.key_name
  vpc_security_group_ids 	= [aws_security_group.getting_started.id]

  tags = merge(local.common_tags, {
    Name = "getting_started"
  })

  connection {
    host        = self.public_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.key.private_key_pem
  }

  # upload files
  provisioner "file" {
    source      = "${path.module}/stuff"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "${path.module}/images"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "${path.module}/toLearn"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "${path.module}/final-mission"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source = "${path.module}/setup_home"
    destination = "/home/ubuntu/setup_home"
  }

  provisioner "file" {
    content = templatefile("${path.module}/install", {
      players = var.students
    })
    destination = "/home/ubuntu/install"
  }
  
  provisioner "file"{
    source = "${path.module}/ttylog"
    destination = "/home/ubuntu/"
  }

  provisioner "file"{
    source = "${path.module}/tty_setup"
    destination = "/home/ubuntu/tty_setup"
  }

  provisioner "file"{
    source = "${path.module}/clear_logs"
    destination = "/home/ubuntu/clear_logs"
  }
  provisioner "file"{
    source = "${path.module}/iamfrustrated"
    destination = "/home/ubuntu/iamfrustrated"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "cloud-init status --wait --long",
      "chmod +x /home/ubuntu/install",
      "chmod +x /home/ubuntu/setup_home",
      "chmod +x /home/ubuntu/tty_setup",
      "chmod +x /home/ubuntu/clear_logs",
      "sudo /home/ubuntu/tty_setup",
      "sudo /home/ubuntu/install",
      "sudo chmod +x /home/ubuntu/iamfrustrated",
      "sudo cp /home/ubuntu/iamfrustrated /usr/bin",
      "sudo cp /home/ubuntu/clear_logs /usr/bin/clear_logs",
      "rm /home/ubuntu/tty_setup",
      "rm /home/ubuntu/install",
      "rm /home/ubuntu/setup_home"
    ]
  }

}

output "instances" {
  value = [{
    name = "getting_started"
    ip_address_public  = aws_instance.getting_started.public_ip
    ip_address_private = aws_instance.getting_started.private_ip
  }]
}

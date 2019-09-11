variable "players" {
  type = list(object({
    login              = string,
    password           = object({ plaintext = string, hash = string }),
    follow_me_filename = string,
    super_secret       = string
  }))
  description = "list of players"
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

provider "aws" {
  profile = "default"
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
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yml.tpl", {
      players = var.players
    })
  }
}

resource "aws_security_group" "getting_started" {
  name = "getting_started"

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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.nano"
  user_data_base64       = data.template_cloudinit_config.getting_started.rendered
  key_name               = aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.getting_started.id]

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
    source      = "stuff"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "images"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "toLearn"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source      = "final-mission"
    destination = "/home/ubuntu"
  }

  provisioner "file" {
    source = "setup_home"
    destination = "/home/ubuntu/setup_home"
  }

  provisioner "file" {
    content = templatefile("${path.module}/install", {
      players = var.players
    })
    destination = "/home/ubuntu/install"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait --long",
      "chmod +x /home/ubuntu/install",
      "chmod +x /home/ubuntu/setup_home",
      "sudo /home/ubuntu/install"
    ]
  }

}

#output "getting_started_public_ip" {
#
#}

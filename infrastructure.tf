provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "us-east-2"
}

resource "aws_key_pair" "immuta-key" {
  key_name   = "immuta-key"
  public_key = "${file("immuta-key.pub")}"
}

resource "aws_security_group" "immuta-web-sg" {
    name        = "immuta-web-sg"
    vpc_id      = "${var.vpc_id}"
    ingress {
        from_port        = 80
        to_port          = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port        = 80
        to_port          = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port        = 443
        to_port          = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port        = 443
        to_port          = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port        = -1
        to_port          = -1
        protocol    = "icmp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    egress {
        from_port        = -1
        to_port          = -1
        protocol    = "icmp"
        cidr_blocks = ["10.0.0.0/16"]
    }


    ingress {
        from_port        = 22
        to_port          = 22
        protocol    = "tcp"
        cidr_blocks = ["${aws_instance.immuta-bastion.private_ip}/32"]
    }

    egress {
        from_port        = 6379
        to_port          = 6379
        protocol         = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }
    

   depends_on = [
      "aws_instance.immuta-bastion"
   ]         
}

resource "aws_security_group" "immuta-db-sg" {
    name        = "immuta-db-sg"
    vpc_id      = "${var.vpc_id}"
    
    ingress {
        from_port        = 6379
        to_port          = 6379
        protocol    = "tcp"
        cidr_blocks = ["${aws_instance.immuta-web.private_ip}/32"]
    }

    egress {
        from_port        = 6379
        to_port          = 6379
        protocol    = "tcp"
        cidr_blocks = ["${aws_instance.immuta-web.private_ip}/32"]
    }

    ingress {
        from_port        = -1
        to_port          = -1
        protocol    = "icmp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    egress {
        from_port        = -1
        to_port          = -1
        protocol    = "icmp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    ingress {
        from_port        = 22
        to_port          = 22
        protocol    = "tcp"
        cidr_blocks = ["${aws_instance.immuta-bastion.private_ip}/32"]
    }

   depends_on = [
      "aws_instance.immuta-bastion"
   ] 
}

resource "aws_security_group" "immuta-bastion-sg" {
    name        = "immuta-bastion-sg"
    vpc_id      = "${var.vpc_id}"
    
    ingress {
        from_port        = 22
        to_port          = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["10.0.0.0/16"]
    }
}

resource "aws_eip" "immuta-web-eip" {
    vpc                         = true
    instance                    = "${aws_instance.immuta-web.id}"

    tags {
        Name = "Immuta-Web-EIP"
    }

    depends_on = [
        "aws_instance.immuta-web"
    ]
}

resource "aws_eip" "immuta-bastion-eip" {
    vpc                         = true
    instance                    = "${aws_instance.immuta-bastion.id}"

    tags {
        Name = "Immuta-Bastion-EIP"
    }

    depends_on = [
        "aws_instance.immuta-bastion"
    ]
}

resource "aws_eip" "immuta-db-eip" {
    vpc                         = true
    instance                    = "${aws_instance.immuta-db.id}"

    tags {
        Name = "Immuta-DB-EIP"
    }

    depends_on = [
        "aws_instance.immuta-db"
    ]
}

resource "aws_instance" "immuta-web" {
  ami                   = "ami-0b59bfac6be064b78"
  instance_type         = "t2.micro"
  subnet_id             = "${var.subnet_id}"  
  vpc_security_group_ids = [
    "${aws_security_group.immuta-web-sg.id}"
  ]

  key_name              = "immuta-key"
  tags {
      Name = "Immuta-Web"
  }

  depends_on = [
      "aws_instance.immuta-bastion",
      "aws_security_group.immuta-web-sg"
  ]
}

resource "aws_instance" "immuta-db" {
  ami                   = "ami-0b59bfac6be064b78"
  instance_type         = "t2.micro"
  subnet_id             = "${var.subnet_id}"
  vpc_security_group_ids = [
    "${aws_security_group.immuta-db-sg.id}"
  ]

  key_name              = "immuta-key"
  tags {
      Name = "Immuta-DB"
  }

  depends_on = [
      "aws_instance.immuta-bastion",
      "aws_security_group.immuta-db-sg"    
  ]
}

resource "aws_instance" "immuta-bastion" {
  ami                    = "ami-0b59bfac6be064b78"
  instance_type          = "t2.micro"
  subnet_id             = "${var.subnet_id}"  
  vpc_security_group_ids = [
    "${aws_security_group.immuta-bastion-sg.id}"
  ]

  key_name              = "immuta-key"

  tags {
      Name = "Immuta-Bastion"
  }
  
  depends_on = [
      "aws_security_group.immuta-bastion-sg"
  ]
}

resource "aws_route53_record" "web-record" {
  zone_id = "${var.public_zone_id}"
  name    = "web.candidate-172.immuta.io"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.immuta-web-eip.public_ip}"]

  depends_on = [
      "aws_instance.immuta-web"
  ]
}
resource "aws_route53_record" "db-record" {
  zone_id = "${var.private_zone_id}"
  name    = "db.candidate-172.immuta.io"
  type    = "A"
  ttl     = "300"
  records = ["${aws_instance.immuta-db.private_ip}"]

  depends_on = [
      "aws_instance.immuta-db"
  ]
}
resource "aws_route53_record" "bastion-record" {
  zone_id = "${var.public_zone_id}"
  name    = "bastion.candidate-172.immuta.io"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.immuta-bastion-eip.public_ip}"]
  
  depends_on = [
      "aws_instance.immuta-bastion"
  ]  
}
provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "wordpress_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-subnet"
  }
}

resource "aws_subnet" "wordpress_subnet_2" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "wordpress-subnet-2"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "wordpress_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "wordpress-rt"
  }
}

resource "aws_route_table_association" "wordpress_rta" {
  subnet_id      = aws_subnet.wordpress_subnet.id
  route_table_id = aws_route_table.wordpress_rt.id
}

resource "aws_route_table_association" "wordpress_rta_2" {
  subnet_id      = aws_subnet.wordpress_subnet_2.id
  route_table_id = aws_route_table.wordpress_rt.id
}

# Web tier security group
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
  description = "Security group for WordPress web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "wordpress-web-sg"
  }
}

# Database tier security group
resource "aws_security_group" "wordpress_db_sg" {
  name        = "wordpress-db-sg"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "wordpress_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.wordpress_subnet.id
  vpc_security_group_ids      = [aws_security_group.wordpress_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  
  tags = {
    Name = "wordpress-instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Remove existing PHP and Apache
              sudo yum remove php php-mysqlnd httpd -y

              # Enable PHP 8.x repository
              sudo amazon-linux-extras enable php8.0

              # Install PHP 8.x, Apache, and MySQL client
              sudo yum install php php-mysqlnd httpd mysql -y

              # Start and enable Apache
              sudo systemctl start httpd
              sudo systemctl enable httpd

              # Remove the Apache test page
              sudo rm -f /var/www/html/index.html

              # Download and install WordPress
              sudo wget https://wordpress.org/latest.tar.gz -P /tmp
              sudo tar -xzf /tmp/latest.tar.gz -C /tmp
              sudo cp -r /tmp/wordpress/* /var/www/html/
              sudo chown -R apache:apache /var/www/html/
              sudo chmod -R 755 /var/www/html/

              # Configure WordPress
              sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
              sudo sed -i "s/database_name_here/${var.db_name}/" /var/www/html/wp-config.php
              sudo sed -i "s/username_here/${var.db_user}/" /var/www/html/wp-config.php
              sudo sed -i "s/password_here/${var.db_password}/" /var/www/html/wp-config.php
              sudo sed -i "s/localhost/$(echo ${aws_db_instance.wordpress_db.endpoint} | cut -f1 -d:)/" /var/www/html/wp-config.php

              # Generate WordPress salts
              SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
              sudo sed -i "/AUTH_KEY/i $SALTS" /var/www/html/wp-config.php

              # Test the database connection
              until mysql -h ${aws_db_instance.wordpress_db.endpoint} -u ${var.db_user} -p${var.db_password} -e "USE ${var.db_name};" > /dev/null 2>&1
              do
                echo "Waiting for database connection..."
                sleep 10
              done
              echo "Database connection successful"

              # Restart Apache
              sudo systemctl restart httpd
              EOF

  depends_on = [aws_db_instance.wordpress_db]
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.wordpress_subnet.id, aws_subnet.wordpress_subnet_2.id]
  
  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

resource "aws_db_instance" "wordpress_db" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine              = "mysql"
  engine_version      = "5.7"
  instance_class      = "db.t3.micro"
  db_name             = var.db_name
  username            = var.db_user
  password            = var.db_password
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot = true
  
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet_group.name
  
  backup_retention_period = 7
  multi_az               = false
  publicly_accessible    = false
  
  tags = {
    Name = "wordpress-db"
  }
}
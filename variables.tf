variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  default     = "ami-0c02fb55956c7d316"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "Wordpress-Key-Pair.pem"
}

variable "db_name" {
  description = "Database name"
  default     = "wordpressdb"
}

variable "db_user" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
}

variable "availability_zone" {
  description = "Availability zone"
  default     = "us-east-1a"
}
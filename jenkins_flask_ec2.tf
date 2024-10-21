# Define AWS provider and region
provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

# Create a Key Pair for SSH access
resource "aws_key_pair" "ec2_key" {
  key_name   = "jenkins-flask-key"
  public_key = file("~/.ssh/id_rsa.pub")  # Replace with the path to your public SSH key
}

# Define a Security Group to allow necessary traffic
resource "aws_security_group" "jenkins_flask_sg" {
  name        = "jenkins_flask_sg"
  description = "Allow SSH, HTTP, and Jenkins"

  # Inbound rules for SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere (adjust this for security)
  }

  # Inbound rule for Flask (Port 5000)
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow Flask from anywhere
  }

  # Inbound rule for Jenkins (Port 8080)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow Jenkins UI from anywhere
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins_flask_sg"
  }
}

# Launch EC2 Instance and install Dockerized Jenkins, Flask web server
resource "aws_instance" "jenkins_flask_instance" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"               # Free-tier eligible instance

  # Associate security group
  vpc_security_group_ids = [aws_security_group.jenkins_flask_sg.id]

  # Use the key pair created earlier
  key_name = aws_key_pair.ec2_key.key_name

  # User data script to install Docker, Jenkins, Python Flask, and run the Flask app
  user_data = <<-EOF
    #!/bin/bash
    # Update and install basic dependencies
    yum update -y
    yum install -y docker python3

    # Start Docker service
    service docker start
    usermod -aG docker ec2-user

    # Install Flask
    pip3 install flask

    # Create a simple Flask app
    cat << 'EOF2' > /home/ec2-user/app.py
    from flask import Flask
    app = Flask(__name__)

    @app.route('/')
    def hello_world():
        return 'Hello from Flask Web Server!'

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5000)
    EOF2

    # Start Flask app in background
    nohup python3 /home/ec2-user/app.py &

    # Pull and run Jenkins in Docker
    docker pull jenkins/jenkins:lts
    docker run -d -p 8080:8080 -p 50000:50000 --name jenkins -v /var/jenkins_home:/var/jenkins_home jenkins/jenkins:lts
  EOF

  # Add a tag to the EC2 instance
  tags = {
    Name = "JenkinsFlaskServer"
  }

  # Block device (optional)
  root_block_device {
    volume_size = 20  # Root volume size in GB
  }

  # Associate a public IP address
  associate_public_ip_address = true
}

# Output the public IP of the EC2 instance
output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.jenkins_flask_instance.public_ip
}

# Output the Flask URL
output "flask_url" {
  description = "Flask Web Server URL"
  value       = "http://${aws_instance.jenkins_flask_instance.public_ip}:5000"
}

# Output the Jenkins URL
output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.jenkins_flask_instance.public_ip}:8080"
}

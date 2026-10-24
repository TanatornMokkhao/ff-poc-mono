# The "before" side: one box running the whole be (api, worker and crons in one container), as FF's
# EC2 runs it under pm2 today. Deploys reach it through SSM Run Command, so it has no SSH port and no
# key to leak; FF's own deploy uses SSH.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Same settings access as the ECS runtime, plus what the box itself needs: pull the image, read the
# database password, and take commands from SSM.
data "aws_iam_policy_document" "ec2" {
  source_policy_documents = [var.runtime_policy_json]
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
  statement {
    actions = [
      "ssm:UpdateInstanceInformation", "ssm:ListAssociations", "ssm:ListInstanceAssociations",
      "ssm:DescribeAssociation", "ssm:GetDocument", "ssm:DescribeDocument",
      "ssm:UpdateInstanceAssociationStatus", "ssm:UpdateAssociationStatus",
      "ssmmessages:*", "ec2messages:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ec2" {
  name                 = "${var.name}-ec2"
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.boundary_arn
}

resource "aws_iam_role_policy" "ec2" {
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "be" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3a.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  user_data                   = <<-EOF
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
  EOF
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }
  tags = { Name = "${var.name}-be" }
  # A newer Amazon Linux image must not replace a running box; the deploy, not Terraform, changes it.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

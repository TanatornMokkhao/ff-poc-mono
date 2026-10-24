# One load balancer in front of both runtimes, as FF's move would run: the listener splits requests
# between the EC2 target group and the ECS one by weight, so traffic moves (and moves back) by
# changing ecs_weight. Group stickiness keeps a client on the side it first reached, which socket.io
# needs while both sides serve.
resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

locals {
  health_check = {
    path                = "/health"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_target_group" "ec2" {
  name                 = "${var.name}-ec2"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  port                 = 3000
  protocol             = "HTTP"
  deregistration_delay = 30
  health_check {
    path                = local.health_check.path
    interval            = local.health_check.interval
    healthy_threshold   = local.health_check.healthy_threshold
    unhealthy_threshold = local.health_check.unhealthy_threshold
    timeout             = local.health_check.timeout
  }
  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}

resource "aws_lb_target_group" "ecs" {
  name                 = "${var.name}-ecs"
  vpc_id               = aws_vpc.this.id
  target_type          = "ip"
  port                 = 3000
  protocol             = "HTTP"
  deregistration_delay = 30
  health_check {
    path                = local.health_check.path
    interval            = local.health_check.interval
    healthy_threshold   = local.health_check.healthy_threshold
    unhealthy_threshold = local.health_check.unhealthy_threshold
    timeout             = local.health_check.timeout
  }
  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.ec2.arn
        weight = 100 - var.ecs_weight
      }
      target_group {
        arn    = aws_lb_target_group.ecs.arn
        weight = var.ecs_weight
      }
      stickiness {
        enabled  = true
        duration = 3600
      }
    }
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.ec2.arn
  target_id        = aws_instance.be.id
  port             = 3000
}

# FF today: one load balancer, every request to the EC2 box. The move to ECS (../ecs) adds a listener
# rule on top of this and never edits the listener itself, so taking ECS away leaves this as it was.
resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "ec2" {
  name                 = "${var.name}-ec2"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  port                 = 3000
  protocol             = "HTTP"
  deregistration_delay = 30
  health_check {
    path                = "/health"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
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
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.ec2.arn
  target_id        = aws_instance.be.id
  port             = 3000
}

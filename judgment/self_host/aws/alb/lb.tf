resource "aws_lb" "judgment_lb" {
  access_logs {
    bucket  = "judgment-alb-access-logs"
    enabled = "true"
  }

  desync_mitigation_mode           = "defensive"
  drop_invalid_header_fields       = "false"
  enable_cross_zone_load_balancing = "true"
  enable_deletion_protection       = "false"
  enable_http2                     = "true"
  enable_waf_fail_open             = "false"
  idle_timeout                     = "300"
  internal                         = "false"
  ip_address_type                  = "ipv4"
  load_balancer_type               = "application"
  name                             = "judgment"
  preserve_host_header             = "false"
  security_groups                  = [var.judgment_lb_sg_id]

  subnets = var.subnet_ids

}

# resource "aws_lb" "rabbitmq_networklb" {
#   enable_cross_zone_load_balancing = "false"
#   enable_deletion_protection       = "false"
#   internal                         = "false"
#   ip_address_type                  = "ipv4"
#   load_balancer_type               = "network"
#   name                             = "rabbitmq-networklb"
#   security_groups                  = ["sg-0260fd52db8edca8a"]

#   subnet_mapping {
#     subnet_id = "subnet-0846b6946a4dfb1e0"
#   }

#   subnet_mapping {
#     subnet_id = "subnet-0d7ec7e93be118205"
#   }

#   subnets = ["subnet-0d7ec7e93be118205", "subnet-0846b6946a4dfb1e0"]

#   tags = {
#     awsApplication = "arn:aws:resource-groups:us-west-1:585008087243:group/Judgment/0ah5py7xkaf45ru9sbpfchokbx"
#   }

#   tags_all = {
#     awsApplication = "arn:aws:resource-groups:us-west-1:585008087243:group/Judgment/0ah5py7xkaf45ru9sbpfchokbx"
#   }
# }

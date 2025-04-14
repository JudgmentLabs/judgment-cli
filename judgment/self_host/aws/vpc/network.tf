# data "aws_subnets" "all_subnets" {
#   filter {
#     name   = "vpc-id"
#     values = [aws_vpc.judgment_vpc.id]
#   }
# }
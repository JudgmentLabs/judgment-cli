output "aws_vpc_judgment_vpc_id" {
  value = "${aws_default_vpc.judgment_vpc.id}"
}

output "all_subnets" {
  value = [
    aws_default_subnet.us-west-1c.id,
    aws_default_subnet.us-west-1b.id
  ]
}

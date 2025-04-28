output "aws_vpc_judgment_vpc_id" {
  value = "${aws_vpc.main.id}"
}

output "all_subnets" {
  value = aws_subnet.public[*].id
}

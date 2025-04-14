resource "aws_default_vpc" "judgment_vpc" {
}

resource "aws_default_subnet" "us-west-1c" {
  availability_zone = "us-west-1c"
}

resource "aws_default_subnet" "us-west-1b" {
  availability_zone = "us-west-1b"
}
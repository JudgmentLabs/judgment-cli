resource "aws_ecs_cluster" "judgmentlabs" {
  name               = "judgmentlabs"
}

resource "aws_ecs_cluster_capacity_providers" "judgmentlabs" {
  cluster_name = aws_ecs_cluster.judgmentlabs.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

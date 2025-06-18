import json
import boto3
import os

def lambda_handler(event, context):
    ecs = boto3.client('ecs')

    message = json.loads(event['Records'][0]['Sns']['Message'])
    repo_name = message.get('detail', {}).get('repository-name')

    print(f"Received push event from repository: {repo_name}")

    # Map repo names to ECS services
    repo_to_service = {
        os.getenv("JUDGMENT_REPO", "judgement"): os.getenv("JUDGMENT_SERVICE", "JudgmentBackendServer"),
        os.getenv("JUDGMENT_WEBSOCKETS_REPO", "judgment-websockets"): os.getenv("JUDGMENT_WEBSOCKETS_SERVICE", "JudgmentWebSocketServer"),
        os.getenv("RUN_EVAL_WORKER_REPO", "run-eval-worker"): os.getenv("RUN_EVAL_WORKER_SERVICE", "RunEvalWorker")
    }

    service_name = repo_to_service.get(repo_name)

    if service_name:
        response = ecs.update_service(
            cluster=os.getenv("ECR_CLUSTER_NAME", "judgmentlabs"),
            service=service_name,
            forceNewDeployment=True
        )
        print(f"Triggered deployment for service: {service_name}")
    else:
        print(f"No matching ECS service for repo: {repo_name}")

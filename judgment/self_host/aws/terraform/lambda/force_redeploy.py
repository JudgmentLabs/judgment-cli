import boto3

def lambda_handler(event, context):
    ecs = boto3.client('ecs')
    ecs.update_service(
        cluster='judgmentlabs',
        service='JudgmentBackendServer',
        forceNewDeployment=True
    )

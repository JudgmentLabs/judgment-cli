import subprocess
import os
import typer
import boto3
import time
import datetime
from ..self_host.supabase.supabase import SupabaseClient

def deploy(creds: dict, supabase_compute_size: str, root_judgment_email: str, root_judgment_password: str, domain_name: str, invitation_email_service: str):
    """Deploy a self-hosted instance of Judgment."""
    supabase_token = creds["supabase_token"]
    org_id = creds["org_id"]
    project_name = "Judgment Database"
    db_password = creds["db_password"]
    # Create Supabase project and get secrets
    supabase_client = SupabaseClient(supabase_token, org_id, db_password)
    supabase_secrets, project_exists = supabase_client.create_project_and_get_secrets(project_name, supabase_compute_size)
    if not project_exists:
        supabase_client.create_root_user(supabase_secrets["supabase_url"], supabase_secrets["supabase_service_role_key"], root_judgment_email, root_judgment_password)
    
    if not typer.confirm("Would you like to proceed with AWS infrastructure deployment?"):
        print("Exiting... You can run the same command you just ran to deploy the AWS infrastructure with the Supabase project that was just created. Just enter 'y' when prompted to use the existing project.")
        raise typer.Exit(0)

    # Change to the AWS directory
    os.chdir(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'self_host', 'aws', 'terraform')))
    
    # Initialize Terraform
    print("Initializing Terraform...")
    subprocess.run(['terraform', 'init'], check=True)
    
    # Prepare the terraform command with variables
    terraform_cmd = (
        f'terraform apply '
        f'-var="supabase_url={supabase_secrets["supabase_url"]}" '
        f'-var="supabase_anon_key={supabase_secrets["supabase_anon_key"]}" '
        f'-var="supabase_service_role_key={supabase_secrets["supabase_service_role_key"]}" '
        f'-var="supabase_jwt_secret={supabase_secrets["supabase_jwt_secret"]}" '
        f'-var="supabase_project_id={supabase_secrets["supabase_project_id"]}" '
        f'-var="openai_api_key={creds.get("openai_api_key", "")}" '
        f'-var="togetherai_api_key={creds.get("togetherai_api_key", "")}" '
        f'-var="anthropic_api_key={creds.get("anthropic_api_key", "")}" '
        f'-var="backend_osiris_api_key={creds.get("osiris_api_key", "")}" '
        f'-var="domain_name={domain_name}" '
        f'-var="invitation_sender_email={creds["invitation_sender_email"]}" '
        f'-var="invitation_sender_app_password={creds["invitation_sender_app_password"]}" '
        f'-var="invitation_email_service={invitation_email_service}" '
        f'-auto-approve'
    )
    

    # Run terraform apply
    print("\nApplying Terraform configuration...")
    subprocess.run(terraform_cmd, shell=True, check=True)

    print("AWS infrastructure deployed successfully!")

    judgment_lb_dns_name = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_lb_dns_name']).decode('utf-8').strip()
    print(f"Judgment self-hosted deployment completed successfully!")
    print(f"You can access your self-hosted Judgment server at:\n\n{judgment_lb_dns_name}\n")

    judgment_certificate_domain_validation_name = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_domain_validation_name']).decode('utf-8').strip()
    judgment_certificate_domain_validation_value = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_domain_validation_value']).decode('utf-8').strip()
    
    print("*** Next step: HTTPS listener setup ***")
    print("As part of deployment, an SSL certificate request was made through ACM. To set up a secure HTTPS listener, the certificate must undergo DNS validation before it can be issued and used by the listener. Additionally, your specified domain name must be mapped to the Judgment load balancer DNS name.\n")
    print("To accomplish this, these two records must be added to your DNS registrar/service.")

    print("\n=== Required DNS Records ===\n")
    print("1. Certificate Validation Record:")
    print(f"   Type:    CNAME")
    print(f"   Name:    {judgment_certificate_domain_validation_name}")
    print(f"   Value:   {judgment_certificate_domain_validation_value}\n")
    
    print("2. Domain Record:")
    print(f"   Type:    CNAME")
    print(f"   Name:    {domain_name}")
    print(f"   Value:   {judgment_lb_dns_name}\n")

    while True:
        if not typer.confirm("Have you copied down these records and/or added them to your DNS registrar/service?"):
            print("Please copy down these records and then press 'y' when asked again...")
        else:
            break

    print("\nYou have the choice to set up the HTTPS listener either now or later. To set up the HTTPS listener later, make sure the above records are added to your DNS registrar/service, then monitor the status of your requested certificate at https://console.aws.amazon.com/acm/home. Once the certificate has status 'Issued', run:\n")
    print("judgment self-host https-listener\n")
    print("to set up the HTTPS listener.\n")
    
    if not typer.confirm("Would you like to continue with the HTTPS listener setup right now?"):
        print("\nThis program will now terminate without setting up the HTTPS listener...\n")
        raise typer.Exit(0)

    print("\nProceeding with HTTPS listener setup...")
    print("Once the two records have been added to your DNS registrar/service, the ACM certificate should be validated and issued shortly after. This program will then continue with the HTTPS listener setup...")
    print("\nChecking ACM certificate status every 30 seconds... You can safely terminate this program during this phase if necessary.")
    acm_client = boto3.client('acm')
    judgment_certificate_arn = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_arn']).decode('utf-8').strip()
    while not is_certificate_issued(judgment_certificate_arn, acm_client):
        time.sleep(30)
    print("\nACM certificate issued! Proceeding with HTTPS listener setup...")
    create_https_listener()

def create_https_listener():
    """
    Create a new HTTPS listener for the Judgment Load Balancer.
    """
    os.chdir(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'self_host', 'aws', 'terraform')))

    try:
        judgment_lb_arn = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_lb_arn']).decode('utf-8').strip()
        judgment_certificate_arn = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_arn']).decode('utf-8').strip()
        backend_target_group_arn = subprocess.check_output(['terraform', 'output', '-raw', 'backend_target_group_arn']).decode('utf-8').strip()
        websocket_target_group_arn = subprocess.check_output(['terraform', 'output', '-raw', 'websocket_target_group_arn']).decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        print(f"Error getting Terraform outputs: {e}")
        print("Did you run 'judgment self-host main' before running this command?")
        raise typer.Exit(1)
    
    os.chdir(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'self_host', 'aws', 'terraform_https_listener')))
    
    print("Initializing Terraform...")
    subprocess.run(['terraform', 'init'], check=True)

    terraform_cmd = (
        f'terraform apply '
        f'-var="judgment_lb_arn={judgment_lb_arn}" '
        f'-var="judgment_certificate_arn={judgment_certificate_arn}" '
        f'-var="backend_target_group_arn={backend_target_group_arn}" '
        f'-var="websocket_target_group_arn={websocket_target_group_arn}" '
        f'-auto-approve'
    )

    print("\nApplying Terraform configuration to create HTTPS listener...")
    subprocess.run(terraform_cmd, shell=True, check=True)

    print("HTTPS listener created successfully!")
    os.chdir(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'self_host', 'aws', 'terraform')))
    domain_name = subprocess.check_output(['terraform', 'output', '-raw', 'domain_name']).decode('utf-8').strip()

    print("You should now be able to access your self-hosted Judgment server at:")
    print(f"https://{domain_name}")
    
def is_certificate_issued(certificate_arn: str, acm_client: boto3.client):
    """
    Get the status of the ACM certificate for the given domain name.
    """
    # Get certificate details
    response = acm_client.describe_certificate(CertificateArn=certificate_arn)
    status = response['Certificate']['Status']

    # Check if the certificate has been issued
    if status == 'ISSUED':
        print(f"Checking ACM certificate status at {datetime.datetime.now()}: Certificate has been issued.")
        return True
    else:
        print(f"Checking ACM certificate status at {datetime.datetime.now()}: Certificate status is: {status}")
        return False
    
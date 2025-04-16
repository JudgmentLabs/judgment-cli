import subprocess
import os
import typer
from ..self_host.supabase.supabase import SupabaseClient

def deploy(creds: dict, supabase_compute_size: str, root_judgment_email: str, root_judgment_password: str, domain_name: str):
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
        f'-var="langfuse_public_key={creds["langfuse_public_key"]}" '
        f'-var="langfuse_secret_key={creds["langfuse_secret_key"]}" '
        f'-var="openai_api_key={creds["openai_api_key"]}" '
        f'-var="togetherai_api_key={creds["togetherai_api_key"]}" '
        f'-var="anthropic_api_key={creds["anthropic_api_key"]}" '
        f'-var="domain_name={domain_name}" '
        f'-auto-approve'
    )
    
    # Run terraform apply
    print("\nApplying Terraform configuration...")
    subprocess.run(terraform_cmd, shell=True, check=True)

    print("AWS infrastructure deployed successfully!")

    judgment_lb_dns_name = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_lb_dns_name']).decode('utf-8').strip()
    print(f"Judgment self-hosted deployment completed successfully!")
    print(f"You can access your self-hosted Judgment server at:\n\n{judgment_lb_dns_name}\n")
    print("Please keep this URL safe.")

    judgment_certificate_domain_validation_name = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_domain_validation_name']).decode('utf-8').strip()
    judgment_certificate_domain_validation_value = subprocess.check_output(['terraform', 'output', '-raw', 'judgment_certificate_domain_validation_value']).decode('utf-8').strip()
    
    print("To set up a secure HTTPS listener, first go to your DNS registrar/service and create two records:")

    print("\n=== Required DNS Records ===\n")
    print("1. Certificate Validation Record:")
    print(f"   Type:    CNAME")
    print(f"   Name:    {judgment_certificate_domain_validation_name}")
    print(f"   Value:   {judgment_certificate_domain_validation_value}\n")
    
    print("2. Domain Record:")
    print(f"   Type:    CNAME")
    print(f"   Name:    {domain_name}")
    print(f"   Value:   {judgment_lb_dns_name}\n")
    
    print("After adding these records, monitor the status of your requested certificate at https://console.aws.amazon.com/acm/home. Once the certificate has status 'Issued', run:")
    print("judgment self-host https-listener")

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
    

    
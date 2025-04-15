import subprocess
import os
from ..self_host.supabase.supabase import SupabaseClient

def deploy(creds: dict, supabase_compute_size: str, root_judgment_email: str, root_judgment_password: str):
    """Deploy a self-hosted instance of Judgment."""
    supabase_token = creds["supabase_token"]
    org_id = creds["org_id"]
    project_name = "Judgment Database"
    db_password = creds["db_password"]
    # Create Supabase project and get secrets
    supabase_client = SupabaseClient(supabase_token, org_id, db_password)
    supabase_secrets = supabase_client.create_project_and_get_secrets(project_name, supabase_compute_size)
    supabase_client.create_root_user(supabase_secrets["supabase_url"], supabase_secrets["supabase_service_role_key"], root_judgment_email, root_judgment_password)
    # Change to the AWS directory
    os.chdir('judgment/self_host/aws/terraform')
    
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
    
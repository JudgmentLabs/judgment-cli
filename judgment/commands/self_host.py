import subprocess
import os
from ..self_host.supabase.create_project import create_project_and_get_secrets

def deploy(supabase_token: str, org_id: str, project_name: str, db_password: str, supabase_compute_size: str):
    """Deploy a self-hosted instance of Judgment."""
    # Create Supabase project and get secrets
    supabase_secrets = create_project_and_get_secrets(supabase_token, org_id, project_name, db_password, supabase_compute_size)
    # Change to the AWS directory
    os.chdir('judgment/self_host/aws')
    
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
        f'-auto-approve'
    )
    
    # Run terraform apply
    print("\nApplying Terraform configuration...")
    subprocess.run(terraform_cmd, shell=True, check=True)
    
    # Print deployment information
    print("\nDeployment completed successfully!")
    
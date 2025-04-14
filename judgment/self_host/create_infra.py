import subprocess
import os
from supabase.create_project import create_project_and_get_secrets

def run_terraform_apply(secrets):
    # Change to the AWS directory
    os.chdir('aws')
    
    # Prepare the terraform command with variables
    terraform_cmd = [
        'terraform', 'apply',
        f'-var="supabase_url={secrets["url"]}"',
        f'-var="supabase_anon_key={secrets["anon_key"]}"',
        f'-var="supabase_service_role_key={secrets["service_role_key"]}"',
        '-auto-approve'
    ]
    
    # Run terraform apply
    subprocess.run(terraform_cmd, check=True)

def main():
    # Create Supabase project and get secrets
    secrets = create_project_and_get_secrets()
    
    # Run terraform apply with the secrets
    run_terraform_apply(secrets)

if __name__ == "__main__":
    main()

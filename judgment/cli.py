import typer
import json
import os
import boto3
import requests
from pathlib import Path
from typing import Optional
from enum import Enum
from .command_utils.self_host import deploy
from typing_extensions import Annotated


app = typer.Typer(help="Judgment CLI tool for managing self-hosted instances.", add_completion=False)

class ComputeSize(str, Enum):
    nano = "nano"
    micro = "micro"
    small = "small"
    medium = "medium"
    large = "large"
    xlarge = "xlarge"
    two_xlarge = "2xlarge"
    four_xlarge = "4xlarge"
    eight_xlarge = "8xlarge"
    twelve_xlarge = "12xlarge"
    sixteen_xlarge = "16xlarge"

@app.command(name="self-host")
def self_host(
    root_judgment_email: Annotated[str, typer.Option(
        "--root-judgment-email",
        "-e",
        help="Email address for the root Judgment user in the self-hosted environment"
    )],
    root_judgment_password: Annotated[str, typer.Option(
        "--root-judgment-password",
        "-p",
        help="Password for the root Judgment user in the self-hosted environment"
    )],
    creds_file: Annotated[Path, typer.Option(
        "--creds-file",
        "-c",
        help="Path to file containing required credentials",
        exists=True,
        readable=True,
        dir_okay=False
    )] = "creds.json", 
    supabase_compute_size: Annotated[ComputeSize, typer.Option(
        "--supabase-compute-size",
        "-s",
        help="Size of the Supabase compute instance"
    )] = "small"
    ):
    """
    Deploy a self-hosted instance of Judgment.
    
    This command will:
    1. Create a new Supabase project
    2. Deploy the AWS infrastructure using Terraform
    3. Configure the application with the necessary credentials
    """
    # Load credentials from file
    try:
        with open(creds_file, 'r') as f:
            creds = json.load(f)
    except json.JSONDecodeError:
        typer.echo("Error: Invalid JSON in credentials file", err=True)
        raise typer.Exit(1)
    
    # Validate required credentials
    required_fields = ['supabase_token', 'org_id', 'db_password', 'langfuse_public_key', 'langfuse_secret_key', 'openai_api_key', 'togetherai_api_key', 'anthropic_api_key']
    missing_fields = [field for field in required_fields if field not in creds]
    if missing_fields:
        typer.echo(f"Error: Missing required fields in credentials file: {', '.join(missing_fields)}", err=True)
        raise typer.Exit(1)
    
    # Get Supabase organization information
    try:
        headers = {
            "Authorization": f"Bearer {creds['supabase_token']}",
            "Content-Type": "application/json"
        }
        org_response = requests.get(
            f"https://api.supabase.com/v1/organizations/{creds['org_id']}",
            headers=headers
        )
        org_response.raise_for_status()
        org_data = org_response.json()
        
        typer.echo(f"\nSupabase Organization Information:")
        typer.echo(f"Organization Name: {org_data['name']}")
        typer.echo(f"Organization ID: {org_data['id']}")
        
        # Check for existing projects
        projects_response = requests.get(
            "https://api.supabase.com/v1/projects",
            headers=headers
        )
        projects_response.raise_for_status()
        existing_projects = [p["name"] for p in projects_response.json() if p["organization_id"] == creds["org_id"]]
        
        if existing_projects:
            typer.echo("\nExisting projects in this organization:")
            for project in existing_projects:
                typer.echo(f"- {project}")
    except Exception as e:
        typer.echo(f"Error getting Supabase organization information: {str(e)}", err=True)
        raise typer.Exit(1)
    
    if not typer.confirm(f"\nAre you sure you want to create a new Supabase project in organization '{org_data['name']}'?"):
        typer.echo("Deployment cancelled.")
        raise typer.Exit(0)
    
    # Get AWS account information
    try:
        sts = boto3.client('sts')
        account_id = sts.get_caller_identity()['Account']
        account_arn = sts.get_caller_identity()['Arn']
        typer.echo(f"\nCurrent AWS Account Information:")
        typer.echo(f"Account ID: {account_id}")
        typer.echo(f"Authenticated User ARN: {account_arn}")
    except Exception as e:
        typer.echo(f"Error getting AWS account information: {str(e)}", err=True)
        raise typer.Exit(1)
    
    if not typer.confirm(f"\nAre you sure you want to deploy Judgment to AWS account {account_id}?"):
        typer.echo("Deployment cancelled.")
        raise typer.Exit(0)

    typer.echo()
    
    
    # Run the deployment
    try:
        deploy(creds, supabase_compute_size, root_judgment_email, root_judgment_password)
    except Exception as e:
        typer.echo(f"Error during deployment: {str(e)}", err=True)
        raise typer.Exit(1)
    
# Still require calling subcommand even if there is only one
@app.callback()
def callback():
    pass

def main():
    app() 

if __name__ == '__main__':
    main()

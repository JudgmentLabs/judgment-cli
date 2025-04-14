import typer
import json
import os
from pathlib import Path
from typing import Optional
from enum import Enum
from .commands.self_host import deploy
from typing_extensions import Annotated

app = typer.Typer(help="Judgment CLI tool for managing self-hosted instances.")

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
        help="Size of the Supabase compute instance",
    )] = "small"):
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
    
    # Run the deployment
    try:
        deploy(creds, supabase_compute_size)
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

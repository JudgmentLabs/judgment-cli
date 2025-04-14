# Judgment CLI Tool

A command-line tool for managing self-hosted instances of Judgment.

## Installation

Install the Judgment CLI:
```bash
pip install -e .
```

## Usage

### Self-Hosting

Make sure Terraform CLI is installed.

On Mac:
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

On Windows:
```bash
choco install terraform
```

On Linux:
Instructions [here](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

To deploy a self-hosted instance of Judgment:

1. Create a credentials file (e.g., `supabase_creds.json`) with the following format:
```json
{
    "supabase_token": "your_supabase_token_here",
    "org_id": "your_organization_id_here",
    "db_password": "your_database_password_here"
}
```

2. Run the self-host command:
```bash
judgment self-host --supabase-creds supabase_creds.json
```

This will:
1. Create a new Supabase project
2. Deploy the AWS infrastructure using Terraform
3. Configure the application with the necessary credentials

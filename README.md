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
    "db_password": "your_database_password_here",
    "langfuse_public_key": "your_langfuse_public_key_here",
    "langfuse_secret_key": "your_langfuse_secret_key_here",
    "openai_api_key": "your_openai_api_key_here",
    "togetherai_api_key": "your_togetherai_api_key_here",
    "anthropic_api_key": "your_anthropic_api_key_here"
}
```

2. Run the self-host command:
```bash
judgment self-host --creds-file creds.json --supabase-compute-size nano
```
*Keep in mind that for `--supabase-compute-size`, only "nano" is available on the free tier of Supabase.*

This will:
1. Create a new Supabase project
2. Deploy the AWS infrastructure using Terraform
3. Configure the application with the necessary credentials
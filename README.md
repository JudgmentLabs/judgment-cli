# Judgment CLI Tool

A command-line tool for Judgment.

## Installation

Clone the repository and install the Judgment CLI:
```bash
git clone https://github.com/JudgmentLabs/judgment-cli.git
cd judgment-cli
pip install -e .
```

## Usage

To see usage information, run:
```bash
judgment --help
```

Available commands:
- `judgment self-host`: Deploy a self-hosted instance of Judgment.

See below for more details on each command.

### Self-Hosting

To see usage information, run:
```bash
judgment self-host --help
```

#### --- Prerequisites ---

**First, make sure AWS CLI is installed and configured.**

On Mac:
```bash
brew install awscli
```

On Windows:
Download and run the installer from [here](https://awscli.amazonaws.com/AWSCLIV2.msi)

On Linux:
```bash
sudo apt install awscli
```

*An empty/new AWS account is required to deploy the infrastructure. After one has been created, configure your local environment with the relevant AWS credentials by running the following command:*
```bash
aws configure
```

**Second, make sure Terraform CLI is installed.**

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

**Third, make sure you have access to a [Supabase account and organization](https://supabase.com/dashboard/sign-in?returnTo=%2Fprojects). This command will automatically create and configure a new Supabase project in this organization.**

#### --- Deploying ---

To deploy a self-hosted instance of Judgment:

1. Create a credentials file (e.g., `creds.json`) with the following format:
```json
{
    "supabase_token": "your_supabase_personal_access_token_here",
    "org_id": "your_supabase_organization_id_here",
    "db_password": "your_desired_supabase_database_password_here",
    "langfuse_public_key": "your_langfuse_public_key_here",
    "langfuse_secret_key": "your_langfuse_secret_key_here",
    "openai_api_key": "your_openai_api_key_here",
    "togetherai_api_key": "your_togetherai_api_key_here",
    "anthropic_api_key": "your_anthropic_api_key_here"
}
```

2. Run the main self-host command with the appropriate arguments. For example:
```bash
judgment self-host main \
--root-judgment-email root@example.com \
--root-judgment-password password \
--domain-name api.example.com \
--creds-file creds.json \
--supabase-compute-size nano
```
*Keep in mind that for `--supabase-compute-size`, only "nano" is available on the free tier of Supabase. If you want to use a larger size, you will need to upgrade your organization to a paid plan.*

This command will:
1. Create a new Supabase project
2. Create a root Judgment user in the self-hosted environment with the email and password provided
3. Deploy the Judgment AWS infrastructure using Terraform
4. Configure the AWS infrastructure to communicate with the new Supabase database
5. \* Request an SSL certificate from AWS Certificate Manager for the domain name provided
6. ** (Optional) Wait for the certificate to be issued and then set up the HTTPS listener

\* For the certificate to be issued, this command will return two DNS records that must be manually added to your DNS registrar/service.

** You will be prompted to either continue with the HTTPS listener setup now or to come back later. If you choose to proceed with the setup now, the program will wait for the certificate to be issued before continuing. If you choose to come back later, refer to the section below for a dedicated HTTPS listener setup command.



#### --- Setting up the HTTPS listener ---
**NOTE: This step is optional; you can choose to have this done as part of the main self-host command.**

**WARNING: This command will only work after `judgment self-host main` has already been run AND the ACM certificate has been issued. To accomplish this, the two records returned by the main self-host command must be added to your DNS registrar/service, and you must monitor the ACM console [here](https://console.aws.amazon.com/acm/home) until the certificate has status 'Issued' before running this command.**

To set up the HTTPS listener, run:
```bash
judgment self-host https-listener
```

This command will:
1. Set up the HTTPS listener with the certificate issued by AWS Certificate Manager
2. Return the url to the HTTPS-enabled domain which now points to your self-hosted Judgment server


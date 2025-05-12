# Judgment CLI

The Judgment CLI is a command-line tool that allows you to manage your Judgment resources and backend infrastructure.

Detailed documentation for this CLI can also be found [here](https://judgment.mintlify.app/judgment_cli/installation).

## Installation

> ⚠️ **Make sure you have Python installed on your system before proceeding with the installation.**

To install the Judgment CLI, follow these steps:

1. Clone the repository:

    ```bash
    git clone https://github.com/JudgmentLabs/judgment-cli.git
    ```

2. Navigate to the project directory:

    ```bash
    cd judgment-cli
    ```

3. Set up a fresh Python virtual environment:

    Choose one of the following methods:

    <details>
    <summary><strong>Built-In venv</strong></summary>

    ```bash
    python -m venv venv
    source venv/bin/activate  # On Windows, use: venv\Scripts\activate
    ```
    </details>

    <details>
    <summary><strong>pipenv</strong></summary>

    ```bash
    pipenv shell
    ```
    </details>

    <details>
    <summary><strong>uv</strong></summary>

    ```bash
    uv venv
    source .venv/bin/activate  # On Windows, use: .venv\Scripts\activate
    ```
    </details>

4. Install the package:

    <details>
    <summary><strong>Built-In</strong></summary>

    ```bash
    pip install -e .
    ```
    </details>

    <details>
    <summary><strong>pipenv</strong></summary>

    ```bash
    pipenv install -e .
    ```
    </details>

    <details>
    <summary><strong>uv</strong></summary>

    ```bash
    uv pip install -e .
    ```
    </details>

## Verifying the Installation

To verify that the CLI was installed correctly, run:

```bash
judgment --help
```

You should see a list of available commands and their descriptions.

## Available Commands

The Judgment CLI provides the following commands:

### Self-Hosting Commands

| Command                              | Description                                                                         |
|--------------------------------------|-------------------------------------------------------------------------------------|
| `judgment self-host main`            | Deploy a self-hosted instance of Judgment (and optionally set up the HTTPS listener) |
| `judgment self-host https-listener` | Set up the HTTPS listener for a self-hosted Judgment instance                      |

---

# Self-Hosting

> ⚠️ **If you are setting up self-hosting for the first time, please read the self-hosting documentation [here](https://judgment.mintlify.app/self_hosting/get_started) *before* you get started with this section!**  

> ⚠️ **Make sure the Judgment CLI is installed before proceeding.**  
> Please refer to the Installation section above for more information.

> ⚠️ **Do not delete `.tfstate` files** generated during setup. They are used by Terraform to track the state of deployed infrastructure.

## Introduction

The `self-host` command is used to deploy and manage your own self-hosted instance of Judgment.

- `self-host main` deploys a Supabase project and the Judgment AWS infrastructure.
- `self-host https-listener` sets up HTTPS and is only needed if you skip it in the `main` command.

## Usage

To see usage information, run:

```bash
judgment self-host --help
judgment self-host main --help
judgment self-host https-listener --help
```

## 1. Prerequisites

> ⚠️ Before proceeding, ensure you have:
>
> 1. An **empty AWS account** registered with us  
> 2. An **Osiris API key** (optional, for evaluations)  
> 3. A valid **email address and app password** (for sending invites)  
> 4. A **Supabase account and organization** with admin access  
> 
> As mentioned above, please read and follow the documentation [here](https://judgment.mintlify.app/self_hosting/get_started) if any of the above aren't set up.

### AWS CLI Setup

Install the AWS CLI:

<details>
<summary><strong>macOS</strong></summary>

```bash
brew install awscli
```
</details>

<details>
<summary><strong>Windows</strong></summary>

Download and run the installer from [AWS CLI MSI](https://awscli.amazonaws.com/AWSCLIV2.msi)
</details>

<details>
<summary><strong>Linux</strong></summary>

```bash
sudo apt install awscli
```
</details>

Then configure it:

```bash
aws configure
```

### Terraform CLI Setup

Terraform is required for AWS infrastructure deployment.

<details>
<summary><strong>macOS</strong></summary>

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```
</details>

<details>
<summary><strong>Windows</strong></summary>

```bash
choco install terraform
```
</details>

<details>
<summary><strong>Linux</strong></summary>

Follow: [Terraform Install Guide](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
</details>

## 2. Deploying

1. Create a `creds.json` file with the following structure:

```json
{
  "supabase_token": "your_supabase_personal_access_token_here",
  "org_id": "your_supabase_organization_id_here",
  "db_password": "your_desired_supabase_database_password_here",
  "invitation_sender_email": "email_address_to_send_org_invitations_from",
  "invitation_sender_app_password": "app_password_for_invitation_sender_email",
  "osiris_api_key": "your_osiris_api_key_here (optional)",
  "openai_api_key": "your_openai_api_key_here (optional)",
  "togetherai_api_key": "your_togetherai_api_key_here (optional)",
  "anthropic_api_key": "your_anthropic_api_key_here (optional)"
}
```

> `supabase_token`: Use an existing one or generate a new one [here](https://supabase.com/dashboard/account/tokens)  

> `org_id`: Extract this from the URL of your Supabase dashboard (make sure you have the correct organization selected in the top left corner). For example, if your organization URL is `https://supabase.com/dashboard/org/uwqswwrmmkxgrkfjkdex`, then your `org_id` is `uwqswwrmmkxgrkfjkdex`

> `db_password` can be any password of your choice. It is necessary for creating the Supabase project and can be used later to directly [connect to the project database](https://supabase.com/docs/guides/database/connecting-to-postgres)

> `invitation_sender_email` and `invitation_sender_app_password` are required because the only way to add users to the self-hosted Judgment instance is via email invitations

> 💡 The four LLM API keys are optional. If you are not planning to run evaluations with the models that require any of these API keys, you do not need to specify them.

2. Run the main self-host command. The command syntax is:
```bash
judgment self-host main [OPTIONS]
```

Required options:

- `--root-judgment-email`, `-e`: Root user email  
- `--root-judgment-password`, `-p`: Root user password  
- `--domain-name`, `-d`: Your domain for SSL

Optional options:
> ⚠️ Supabase free tier only supports `nano` for `--supabase-compute-size`. Larger sizes require a paid plan.

- `--creds-file`, `-c`: Path to your `creds.json` (default: `creds.json`)  
- `--supabase-compute-size`, `-s`: Supabase instance size (default: `small`)  
- `--invitation-email-service`, `-i`: Email provider (default: `gmail`)

Example usage:
```bash
judgment self-host main \
  --root-judgment-email root@example.com \
  --root-judgment-password password \
  --domain-name api.example.com \
  --creds-file creds.json \
  --supabase-compute-size nano \
  --invitation-email-service gmail
```

What this command does:

1. Creates a new Supabase project  
2. Sets up the root Judgment user  
3. Deploys AWS infrastructure  
4. Connects AWS services to Supabase  
5. Requests an SSL certificate  
6. Optionally configures the HTTPS listener

> 📘 For SSL, you'll be given two DNS records to manually add to your DNS registrar.  

> 🕒 After steps 1-5, you will be prompted to either continue with the HTTPS listener setup now or to come back later. If you choose to proceed with the setup now, the program will wait for the certificate to be issued before continuing.

## 3. Setting up the HTTPS Listener
> ⚠️ This step is optional; you can choose to have the HTTPS listener setup done as part of the main self-host command.

> ⚠️ This command will only work after `judgment self-host main` has already been run AND the ACM certificate has been issued. To accomplish this:
> 1. Add the two DNS records returned by the main self-host command to your DNS registrar/service
> 2. Monitor the ACM console [here](https://console.aws.amazon.com/acm/home) until the certificate has status ‘Issued’

After your ACM SSL certificate has been issued, set up the HTTPS listener by running the following:

```bash
judgment self-host https-listener
```

This command:

1. Sets up the HTTPS listener with your certificate  
2. Returns the final HTTPS endpoint of your self-hosted Judgment server

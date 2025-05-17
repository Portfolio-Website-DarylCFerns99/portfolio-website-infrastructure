# Required GitHub Secrets for CI/CD Workflow

For the CI/CD workflow to function properly, you need to set up the following secrets in your GitHub repository:

## Required Secrets

| Secret Name | Description |
|-------------|-------------|
| `GCP_PROJECT_ID` | Your Google Cloud project ID |
| `GCP_SA_KEY` | Base64-encoded service account key JSON with necessary permissions |
| `GCP_REGION` | GCP region for deployments (e.g., `us-central1`) |
| `TF_STATE_BUCKET` | GCS bucket name for storing Terraform state |
| `PROJECT_NAME` | Name prefix for all GCP resources |
| `DOMAIN_NAME` | Your domain name (e.g., `example.com`) |
| `SSL_PRIVATE_KEY` | Content of your SSL private key |
| `SSL_CERTIFICATE` | Content of your SSL certificate |

## Service Account Permissions

The GCP service account used needs the following roles:
- Compute Admin (`roles/compute.admin`)
- Kubernetes Engine Admin (`roles/container.admin`)
- Storage Admin (`roles/storage.admin`)
- Service Account User (`roles/iam.serviceAccountUser`)

## How to Generate a Service Account Key

1. Go to the Google Cloud Console > IAM & Admin > Service Accounts
2. Create a new service account or select an existing one
3. Grant the necessary roles
4. Create a new JSON key
5. Base64 encode the key:
   ```bash
   cat your-key.json | base64 -w 0
   ```
6. Use the output as the value for `GCP_SA_KEY`

## Setting up the Terraform State Bucket

Before the first run, you need to create a GCS bucket for storing the Terraform state:

```bash
gsutil mb -l us-central1 gs://your-tf-state-bucket
gsutil versioning set on gs://your-tf-state-bucket
```

Use the bucket name as the value for `TF_STATE_BUCKET`.

## SSL Certificate

You need to provide your SSL certificate and private key as GitHub secrets. The workflow will create the corresponding files during execution.

If you don't have a certificate yet, you can:
1. Use a service like Let's Encrypt to generate one
2. Purchase one from a certificate authority
3. For testing, generate a self-signed certificate:
   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout private.key -out certificate.crt
   ```

Copy the entire content of these files (including the BEGIN and END lines) into the corresponding GitHub secrets.
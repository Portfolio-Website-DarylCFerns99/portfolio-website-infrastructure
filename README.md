# Vite + ReactJS Frontend with FastAPI Backend on GCP

This repository contains Terraform configuration for deploying a complete infrastructure on Google Cloud Platform for a modern web application architecture.

## Architecture

![Architecture Diagram]()

The infrastructure includes:

1. **Frontend**: Vite + React served from Google Cloud Storage via Cloud CDN
2. **Backend**: FastAPI on Google Kubernetes Engine (GKE)
3. **Networking**: Cloud Load Balancer with path-based routing to serve both components on a single domain

## Features

- **Self-contained Infrastructure**: All required GCP APIs are enabled automatically
- **Comprehensive Logging**: Logs from all components are streamed to Google Cloud Logging
- **Simplified DNS Management**: 
  - Single source of truth for all DNS records in a map structure
  - Automatic root domain A record pointing to load balancer IP
  - Support for SendGrid email configuration out of the box
- **Enhanced Security**:
  - Private GKE nodes
  - HTTPS with SSL certificate
  - Restricted firewall rules
  - Optional domain-based egress control
- **Production-Ready**: Load balancing, CDN, auto-scaling, and more
- **Helper Scripts**: Streamlined deployment and cleanup scripts for easier testing

## Prerequisites

- Google Cloud Platform account with billing enabled
- Terraform (v1.0.0+)
- SSL certificate and private key for your domain
- Docker image for your FastAPI backend (or you'll need to build and push one)

## Setup Instructions

### 1. Clone this repository

```bash
git clone https://github.com/your-username/infrastructure.git
cd infrastructure
```

### 2. Configure Terraform variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set your:
- GCP project ID
- Project name
- Domain name
- Path to SSL certificate files
- Container image for the backend
- DNS records (all records except the root domain are defined here)

### 3. Generate SSL certificates (for testing only)

For testing, you can generate self-signed certificates:

```bash
chmod +x generate-cert.sh
./generate-cert.sh yourdomain.com
```

For production, use a trusted certificate authority.

### 4. Deploy with the Helper Script (Recommended)

The easiest way to deploy the infrastructure is using the provided helper script:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
- Guide you through setting up required variables if needed
- Generate self-signed SSL certificates if they don't exist
- Create a Terraform state bucket automatically
- Initialize Terraform with the remote backend
- Plan and apply the infrastructure changes
- Display useful outputs after deployment

### 5. Manual Deployment (Alternative)

If you prefer to deploy manually, you can follow these steps:

#### 5.1 Initialize Terraform

Create a GCS bucket for Terraform state:

```bash
PROJECT_ID="your-gcp-project-id"
gsutil mb -l us-central1 gs://${PROJECT_ID}-tf-state
gsutil versioning set on gs://${PROJECT_ID}-tf-state
```

Initialize Terraform with remote state:

```bash
terraform init \
  -backend-config="bucket=${PROJECT_ID}-tf-state" \
  -backend-config="prefix=terraform/state"
```

#### 5.2 Plan and apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

## DNS Configuration

The infrastructure uses a simplified approach to DNS management:

1. **Root Domain A Record**: Automatically created pointing to the load balancer IP address
2. **All Other DNS Records**: Defined in the `dns_records` map in terraform.tfvars

Example DNS records configuration:

```hcl
dns_records = {
  # SendGrid email verification
  "em8516" = {
    record_type = "CNAME"
    ttl         = 3600
    records     = ["u51965170.wl171.sendgrid.net."]
    zone_name   = "your-zone-name"
  },
  
  # WWW subdomain
  "www" = {
    record_type = "CNAME"
    ttl         = 3600
    records     = ["your-domain.com."]
    zone_name   = "your-zone-name"
  }
}
```

To add a new DNS record, simply add a new entry to the `dns_records` map and apply the changes.

## Post-Deployment Steps

1. Configure DNS to point your domain to the load balancer IP address (shown in the outputs)
   - *Note: If using Cloud DNS (dns_zone_name is set), the root domain A record is created automatically*
2. Push your frontend assets to the created Cloud Storage bucket
3. Verify that the Kubernetes service is running

## Clean Up

### Option A: Using the Helper Script (Recommended)

For a safer and more thorough cleanup process, use the provided cleanup script:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

The cleanup script will:
- Confirm before proceeding with destructive actions
- Run terraform destroy to remove all infrastructure
- Optionally delete local configuration files (terraform.tfvars)
- Optionally delete SSL certificate files
- Optionally delete the Terraform state bucket
- Provide detailed feedback during the cleanup process

### Option B: Manual Cleanup

To delete all created resources manually:

```bash
terraform destroy
```

## Output Information

After successful deployment, Terraform will output:
- Load balancer IP
- Frontend bucket name
- Kubernetes cluster name
- Command to get kubectl credentials
- API and frontend URLs
- DNS configuration instructions
- List of enabled GCP APIs
- Summary of configured DNS records

## Common Issues and Troubleshooting

### API Enablement
The infrastructure automatically enables all required APIs, but this can take time. If you encounter errors about disabled APIs, try running `terraform apply` again after a few minutes.

### GKE Cluster Creation
GKE clusters can take 5-10 minutes to fully create and provision. Be patient during this step.

### SSL Certificate Issues
Ensure your SSL certificate files are in PEM format and cover the domain you're using.

### IAM Permission Issues
Ensure your GCP account has sufficient permissions. You need at least:
- Compute Admin
- Kubernetes Engine Admin
- Storage Admin
- Service Account User
- IAM Admin
- Logging Admin
- BigQuery Admin

### DNS Issues
- If using Cloud DNS, verify that your domain's nameservers are updated to point to Google's nameservers
- If using external DNS, manually create an A record for the root domain pointing to the load balancer IP

### Helper Script Issues
- If you encounter permission issues with the helper scripts, ensure they're executable: `chmod +x *.sh`
- On Windows, consider using WSL or Git Bash to run the bash scripts
- Check that your GCP credentials are properly configured before running the scripts

## Customization

The infrastructure is designed to be customizable. Common customizations include:

- Changing machine types for GKE nodes (`gke_machine_type` variable)
- Adjusting the number of GKE nodes (`gke_num_nodes` variable)
- Configuring egress restrictions (`allowed_egress_domains` variable)
- Modifying subnet CIDRs for advanced networking
- Adding custom DNS records to the `dns_records` map

## Files Overview

- `main.tf` - Main infrastructure definition
- `variables.tf` - Variable definitions
- `outputs.tf` - Output declarations
- `terraform.tfvars.example` - Example variable values with DNS configuration
- `generate-cert.sh` - Helper script to generate test SSL certificates
- `deploy.sh` - Helper script for streamlined deployment
- `cleanup.sh` - Helper script for thorough cleanup
- `.gitignore` - Git ignore rules
- `PROJECT_OVERVIEW.md` - Detailed overview of project components

## Next Steps

After deploying the infrastructure, you'll need to:

1. Deploy your FastAPI backend to the GKE cluster
2. Upload your Vite + React frontend to the Cloud Storage bucket
3. Set up a CI/CD pipeline to automate future deployments

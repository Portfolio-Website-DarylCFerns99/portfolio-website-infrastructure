#!/bin/bash
# Use the set command to debug commands (this command will display all the commands that are being run in this script file)
# set -x 

# Helper script to deploy the infrastructure

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed. Please install it first."
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud is not installed. Please install the Google Cloud SDK first."
    exit 1
fi

# Function to prompt for variables if terraform.tfvars doesn't exist
create_tfvars() {
    echo "Creating terraform.tfvars file..."
    
    # Prompt for required variables
    read -p "Enter your GCP Project ID: " tmp_project_id
    declare -g project_id="$tmp_project_id"
    read -p "Enter a name for this project: " project_name
    read -p "Enter GCP region (default: us-central1): " tmp_region
    declare -g region=${tmp_region:-us-central1}
    read -p "Enter your domain name: " tmp_domain
    declare -g domain_name="$tmp_domain"
    read -p "Enter container image for backend (e.g., gcr.io/$project_id/fastapi-app:latest): " api_container_image

    # Create terraform.tfvars file
    cat > terraform.tfvars << EOF
# Generated terraform.tfvars file
project_id           = "$project_id"
project_name         = "$project_name"
region               = "$region"
domain_name          = "$domain_name"
api_container_image  = "$api_container_image"
ssl_private_key_path = "./private.key"
ssl_certificate_path = "./certificate.crt"
EOF

    echo "terraform.tfvars file created successfully."
}

# Function to generate self-signed SSL certificate
generate_ssl_cert() {
    if [[ ! -f private.key || ! -f certificate.crt ]]; then
        echo "Generating self-signed SSL certificate..."
        ./generate-cert.sh "$domain_name"
        chmod 600 private.key certificate.crt
    else
        echo "SSL certificate files already exist."
    fi
}

# Function to create GCS bucket for Terraform state
create_state_bucket() {
    echo "Creating GCS bucket for Terraform state..."

    # Ensure project_id is set
    if [ -z "${project_id}" ]; then
        echo "ERROR: project_id is not set or empty"
        read -p "Please enter your GCP Project ID: " project_id
    fi

    # Ensure region is set
    if [ -z "${region}" ]; then
        echo "ERROR: region is not set or empty"
        read -p "Please enter your GCP Region: " region
    fi

    # Create bucket name explicitly
    bucket_name="${project_id}-tf-state"

    # Check if bucket already exists
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        echo "State bucket already exists: gs://${bucket_name}"
    else
        echo "Creating bucket in region ${region} ..."
        echo "${region}" "gs://${bucket_name}"
        gsutil mb -l "${region}" "gs://${bucket_name}" || {
            echo "Failed to create bucket"
            return 1
        }
        gsutil versioning set on "gs://${bucket_name}" || {
            echo "Failed to enable versioning"
            return 1
        }
        echo "Created state bucket: gs://${bucket_name}"
    fi
}

# Function to initialize Terraform
init_terraform() {
    echo "Initializing Terraform with remote state..."
    bucket_name="${project_id}-tf-state"
    terraform fmt .
    terraform init \
      -backend-config="bucket=${bucket_name}" \
      -backend-config="prefix=terraform/state"
}

# Function to run Terraform plan
plan_terraform() {
    echo "Running Terraform plan..."
    terraform plan -out=tfplan
}

# Function to apply Terraform configuration
apply_terraform() {
    echo "Applying Terraform configuration..."
    terraform apply tfplan
}

# Main script execution
echo "==== GCP Infrastructure Deployment Script ===="
echo ""

# Check if terraform.tfvars exists
if [[ ! -f terraform.tfvars ]]; then
    create_tfvars
else
    echo "Using existing terraform.tfvars file."
    # Read project_id, domain_name and region from existing file
    project_id=$(grep "project_id" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
    domain_name=$(grep "domain_name" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
    region=$(grep "region" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
fi

# Generate SSL certificate if needed
generate_ssl_cert

# Create state bucket
create_state_bucket

# Initialize Terraform
init_terraform

# Plan Terraform deployment
plan_terraform

# Ask for confirmation before applying
read -p "Review the plan above. Do you want to deploy? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    apply_terraform

    echo ""
    echo "==== Deployment Complete ===="
    echo ""
    echo "Next steps:"
    echo "1. Configure DNS for your domain to point to the load balancer IP"
    echo "2. Deploy your frontend to the Cloud Storage bucket"
    echo "3. Verify the backend service is running in GKE"
    echo ""
    echo "To get information about your deployment, run: terraform output"
else
    echo "Deployment cancelled."
fi

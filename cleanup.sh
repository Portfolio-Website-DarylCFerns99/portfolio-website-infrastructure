#!/bin/bash
# Helper script to clean up resources after the deployment is no longer needed

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed. Please install it first."
    exit 1
fi

# Function to ask for confirmation
confirm_action() {
    read -p "$1 (y/n): " confirm
    if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
        return 0
    else
        return 1
    fi
}

echo "=== Infrastructure Cleanup Script ==="
echo ""
echo "WARNING: This script will destroy all infrastructure resources created by Terraform."
echo "This action is IRREVERSIBLE and will result in DATA LOSS."
echo ""

if confirm_action "Are you sure you want to continue?"; then
    echo "Proceeding with cleanup..."
    
    echo "Running terraform destroy..."
    terraform destroy

    if [ $? -eq 0 ]; then
        echo "Terraform resources successfully destroyed."
        
        # Ask if the user wants to delete terraform.tfvars
        if [ -f "terraform.tfvars" ] && confirm_action "Do you want to delete terraform.tfvars?"; then
            rm terraform.tfvars
            echo "terraform.tfvars deleted."
        fi
        
        # Ask if the user wants to delete SSL certificate files
        if [ -f "private.key" ] && [ -f "certificate.crt" ] && confirm_action "Do you want to delete SSL certificate files?"; then
            rm private.key certificate.crt
            echo "SSL certificate files deleted."
        fi
        
        # Ask if the user wants to delete the Terraform state bucket
        if confirm_action "Do you want to delete the Terraform state bucket?"; then
            # Try to extract project_id from terraform.tfvars or .terraform directory
            if [ -f "terraform.tfvars" ]; then
                project_id=$(grep "project_id" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
            fi

            # Use the project_id from above or ask again if not available
            if [ -z "$project_id" ]; then
                read -p "Enter your GCP project ID: " project_id
            fi

            gsutil rm -r "gs://${project_id}-tf-state"
            echo "Terraform state bucket deleted."
        fi
        
        # Ask if the user wants to delete the container images from Artifact Registry
        if confirm_action "Do you want to delete the container images from Artifact Registry?"; then
            # Try to extract project_id from terraform.tfvars or .terraform directory
            if [ -f "terraform.tfvars" ]; then
                project_id=$(grep "project_id" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
            fi

            # Use the project_id from above or ask again if not available
            if [ -z "$project_id" ]; then
                read -p "Enter your GCP project ID: " project_id
            fi
            
            if [ -n "$project_id" ]; then
                # Delete the container images first
                echo "Deleting container images from gcr.io/${project_id}/fastapi-app"
                gcloud container images list-tags "gcr.io/${project_id}/fastapi-app" --format='get(digest)' | xargs -I {} gcloud container images delete --quiet --force-delete-tags "gcr.io/${project_id}/fastapi-app@{}" || true
                
                # Try to delete the repository by using the gcr.io URI directly
                echo "Attempting to remove the repository entirely"
                gcloud container images delete --quiet "gcr.io/${project_id}/fastapi-app" || echo "Note: This command may fail which is expected. The repository is considered deleted when all images are removed."
                
                echo "Container images cleanup completed. If the repository still exists, you may need to delete any remaining tags manually."
            else
                echo "Project ID not provided. Skipping container image deletion."
            fi
        fi
        
        echo "Cleanup complete!"
    else
        echo "Terraform destroy failed. Some resources may still exist."
        exit 1
    fi
else
    echo "Cleanup cancelled."
fi

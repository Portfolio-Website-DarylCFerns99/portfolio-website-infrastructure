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
            project_id=""
            if [ -f "terraform.tfvars" ]; then
                project_id=$(grep "project_id" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
            fi
            
            if [ -n "$project_id" ]; then
                read -p "Enter the project ID to confirm deletion of gs://${project_id}-tf-state: " confirm_project_id
                if [ "$project_id" == "$confirm_project_id" ]; then
                    gsutil rm -r "gs://${project_id}-tf-state"
                    echo "Terraform state bucket deleted."
                else
                    echo "Project ID doesn't match. Skipping state bucket deletion."
                fi
            else
                read -p "Project ID not found. Enter your project ID: " project_id
                read -p "Enter the project ID again to confirm deletion of gs://${project_id}-tf-state: " confirm_project_id
                if [ "$project_id" == "$confirm_project_id" ]; then
                    gsutil rm -r "gs://${project_id}-tf-state"
                    echo "Terraform state bucket deleted."
                else
                    echo "Project IDs don't match. Skipping state bucket deletion."
                fi
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

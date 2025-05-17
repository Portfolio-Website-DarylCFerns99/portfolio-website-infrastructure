#!/bin/bash
# Helper script to automate the SSL certificate creation for testing purposes

# Check if openssl is installed
if ! command -v openssl &> /dev/null; then
    echo "Error: openssl is not installed. Please install it first."
    exit 1
fi

# Define the domain name
if [ -z "$1" ]; then
    read -p "Enter domain name (e.g., example.com): " DOMAIN
else
    DOMAIN=$1
fi

echo "Generating SSL certificate for $DOMAIN..."

# Generate a private key
openssl genrsa -out private.key 2048

# Generate a CSR (Certificate Signing Request)
openssl req -new -key private.key -out certificate.csr -subj "/CN=$DOMAIN/O=Test Organization/C=US"

# Generate a self-signed certificate valid for 365 days
openssl x509 -req -days 365 -in certificate.csr -signkey private.key -out certificate.crt

# Clean up CSR file
rm certificate.csr

echo "SSL certificate generation complete!"
echo "  - Private key saved to: private.key"
echo "  - Certificate saved to: certificate.crt"
echo ""
echo "⚠️  Note: This is a self-signed certificate for testing only."
echo "   For production, obtain a certificate from a trusted CA."
echo ""

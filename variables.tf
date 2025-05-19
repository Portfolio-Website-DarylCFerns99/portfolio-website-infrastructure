# Variables for GCP deployment

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_name" {
  description = "A name for the project that will be used to generate resource names"
  type        = string
  default     = "vite-fastapi"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# VPC and Subnet CIDRs
variable "gke_type" {
  description = "Type of GKe cluster to be crceated (Regional or Zonal)"
  type        = string
  default     = "region"
}

variable "gke_subnet_cidr" {
  description = "CIDR for the GKE subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "gke_pods_cidr" {
  description = "CIDR for GKE pods"
  type        = string
  default     = "10.16.0.0/14"
}

variable "gke_services_cidr" {
  description = "CIDR for GKE services"
  type        = string
  default     = "10.20.0.0/20"
}

variable "gke_master_cidr" {
  description = "CIDR for GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

# GKE cluster variables
variable "gke_num_nodes" {
  description = "Number of GKE nodes"
  type        = number
  default     = 2
}

variable "gke_instance_node_zone" {
  description = "GKE node instance zone"
  type        = string
  default     = "us-east1b"
}

variable "gke_machine_disk_size_gb" {
  description = "GKE node machine disk size in GB"
  type        = number
  default     = 10
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-standard-2"
}

# Container image for the API
variable "api_container_image" {
  description = "Container image for the FastAPI application"
  type        = string
}

# SSL certificate paths
variable "ssl_private_key_path" {
  description = "Path to the SSL private key file"
  type        = string
}

variable "ssl_certificate_path" {
  description = "Path to the SSL certificate file"
  type        = string
}

# Load balancer IP ranges - for restricting access to GKE
variable "load_balancer_ip_ranges" {
  description = "CIDR ranges for load balancer"
  type        = string
  default     = "130.211.0.0/22,35.191.0.0/16" # Google Cloud Load Balancer ranges
}

# Optionally add specific domain restrictions for outbound traffic
variable "allowed_egress_domains" {
  description = "List of domains allowed for egress traffic from GKE"
  type        = list(string)
  default     = [] # Empty means no restrictions
}

# IP ranges for allowed egress domains (resolved manually)
variable "allowed_egress_ip_ranges" {
  description = "CIDR ranges for allowed egress domains"
  type        = list(string)
  default     = [] # Should be populated with IP ranges for allowed_egress_domains
}

# DNS Zone configuration
variable "dns_zone_name" {
  description = "The name of the DNS zone (set to empty string if using external DNS)"
  type        = string
  default     = ""
}

# DNS Records map for all DNS records except the root domain
variable "dns_records" {
  description = "Map of DNS records to create (excluding root domain record which is created automatically)"
  type = map(object({
    record_type = string       # Record type (A, CNAME, TXT, MX, etc.)
    ttl         = number       # Time to live in seconds
    records     = list(string) # Record values (IPs, hostnames, text values)
    zone_name   = string       # DNS zone name (should match dns_zone_name)
  }))
  default = {}
}

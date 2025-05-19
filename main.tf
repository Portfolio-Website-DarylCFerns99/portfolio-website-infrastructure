terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  # Remote backend configuration - GCS bucket
  backend "gcs" {
    # Bucket and prefix configured in terraform init command
    # or can be specified directly here
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable required GCP APIs/Services
locals {
  required_services = [
    "compute.googleapis.com",              # Compute Engine API
    "container.googleapis.com",            # Kubernetes Engine API
    "iam.googleapis.com",                  # Identity and Access Management API
    "storage.googleapis.com",              # Cloud Storage API
    "logging.googleapis.com",              # Cloud Logging API
    "bigquery.googleapis.com",             # BigQuery API
    "cloudresourcemanager.googleapis.com", # Cloud Resource Manager API
    "monitoring.googleapis.com",           # Cloud Monitoring API
    "serviceusage.googleapis.com",         # Service Usage API
    "stackdriver.googleapis.com",          # Stackdriver API
    "iamcredentials.googleapis.com",       # IAM Credentials API
    "dns.googleapis.com"                   # Cloud DNS API (for DNS configuration)
  ]
  clean_timestamp = time_static.activation_date.unix
}

resource "time_static" "activation_date" {}

resource "google_project_service" "required_services" {
  for_each = toset(local.required_services)

  project = var.project_id
  service = each.value

  # Don't disable the service if the terraform configuration is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Kubernetes provider configuration - we dynamically connect to our GKE cluster
data "google_client_config" "default" {
  depends_on = [google_project_service.required_services]
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Create a logs bucket for centralized logging
resource "google_storage_bucket" "portfolio_logs_bucket" {
  name          = "${var.project_name}-logs-bucket-${local.clean_timestamp}"
  location      = var.region
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 90 # days
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_services]
}

# Create a log sink for GKE pods
resource "google_logging_project_sink" "gke_logs" {
  name        = "${var.project_name}-gke-logs"
  description = "Export all GKE container logs to dedicated log bucket"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/kubernetes-logs-${local.clean_timestamp}"
  filter      = "resource.type=k8s_container AND resource.labels.cluster_name=${google_container_cluster.primary.name}"

  unique_writer_identity = true

  depends_on = [
    google_project_service.required_services,
    google_logging_project_bucket_config.kubernetes_logs
  ]
}

# Create a log bucket specifically for GKE
resource "google_logging_project_bucket_config" "kubernetes_logs" {
  project        = var.project_id
  location       = "global"
  retention_days = 30
  bucket_id      = "kubernetes-logs-${local.clean_timestamp}"

  depends_on = [google_project_service.required_services]
}

# Grant permissions to the log sink writer
# resource "google_project_iam_binding" "log_writer" {
#   project = var.project_id
#   role    = "roles/logging.configWriter"

#   members = google_logging_project_sink.gke_logs.writer_identity

#   depends_on = [
#     google_logging_project_sink.gke_logs,
#     google_project_service.required_services
#   ]
# }

# VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required_services]
}

# Subnet for GKE cluster with VPC flow logs
resource "google_compute_subnetwork" "gke_subnet" {
  name          = "${var.project_name}-gke-subnet"
  ip_cidr_range = var.gke_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id

  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.gke_services_cidr
  }

  # Enable VPC flow logs for network debugging
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}

# Firewall rule for GKE API server with logging
resource "google_compute_firewall" "gke_api" {
  name    = "${var.project_name}-gke-api"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  # Only allow traffic from the load balancer subnet(s)
  source_ranges = split(",", var.load_balancer_ip_ranges)
  target_tags   = ["gke-node"]

  # Log firewall hits
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}

# Cloud NAT for outbound traffic from private GKE nodes
resource "google_compute_router" "router" {
  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.vpc_network.id

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Enhanced logging for NAT traffic
  log_config {
    enable = true
    filter = "ALL" # Log all traffic, not just errors
  }

  depends_on = [google_compute_router.router]
}

# Custom SSL certificate (instead of Google-managed)
resource "google_compute_ssl_certificate" "default" {
  name        = "${var.project_name}-ssl-cert"
  private_key = file(var.ssl_private_key_path)
  certificate = file(var.ssl_certificate_path)

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.required_services]
}

# Cloud Storage bucket for static assets
resource "google_storage_bucket" "frontend_bucket" {
  name          = "${var.project_name}-static-assets-${local.clean_timestamp}"
  location      = var.region
  force_destroy = true

  # Recommended settings for website hosting
  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # For SPA routing
  }

  # Make objects publicly readable
  uniform_bucket_level_access = true

  cors {
    origin          = ["https://${var.domain_name}"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Access-Control-Allow-Origin"]
    max_age_seconds = 3600
  }

  # Enable bucket logging
  logging {
    log_bucket        = google_storage_bucket.portfolio_logs_bucket.name
    log_object_prefix = "frontend-bucket-logs"
  }

  depends_on = [
    google_project_service.required_services,
    google_storage_bucket.portfolio_logs_bucket
  ]
}

# IAM policy for public read access to bucket
resource "google_storage_bucket_iam_binding" "public_read" {
  bucket = google_storage_bucket.frontend_bucket.name
  role   = "roles/storage.objectViewer"
  members = [
    "allUsers",
  ]

  depends_on = [google_storage_bucket.frontend_bucket]
}

# Backend service for Cloud CDN
resource "google_compute_backend_bucket" "cdn_backend" {
  name        = "${var.project_name}-cdn-backend"
  bucket_name = google_storage_bucket.frontend_bucket.name
  enable_cdn  = true

  cdn_policy {
    cache_mode       = "CACHE_ALL_STATIC"
    client_ttl       = 3600
    default_ttl      = 3600
    max_ttl          = 86400
    negative_caching = true
  }

  depends_on = [google_storage_bucket.frontend_bucket]
}

# GKE cluster - private nodes with built-in logging
resource "google_container_cluster" "primary" {
  name     = "${var.project_name}-gke-cluster"
  location = var.gke_type == "region" ? var.region : var.gke_instance_node_zone

  # We create the smallest possible default node pool and immediately delete it
  remove_default_node_pool = true
  initial_node_count       = 1

  # Networking configuration
  network    = google_compute_network.vpc_network.self_link
  subnetwork = google_compute_subnetwork.gke_subnet.self_link

  # IP allocation policy for GKE
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.gke_master_cidr
  }

  # Enable workload identity for better security
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable network policy for better pod security
  network_policy {
    enabled = true
  }

  # Enable shielded nodes for better security
  node_config {
    shielded_instance_config {
      enable_secure_boot = true
    }
  }

  # Enable logging and monitoring
  # logging_config {
  #   enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  # }

  # monitoring_config {
  #   enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  # }

  depends_on = [
    google_project_service.required_services,
    google_compute_subnetwork.gke_subnet
  ]
}

# Node pool for the GKE cluster
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.project_name}-node-pool"
  location   = var.gke_type == "region" ? var.region : var.gke_instance_node_zone
  cluster    = google_container_cluster.primary.name
  node_count = var.gke_num_nodes

  node_config {
    disk_size_gb = var.gke_machine_disk_size_gb
    machine_type = var.gke_machine_type

    # Set oauth scopes for the nodes - enable full logging and monitoring
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/trace.append"
    ]

    labels = {
      env = var.project_name
    }

    tags = ["gke-node"]

    # Enable workload identity on the node pool
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Enable shielded nodes for better security
    shielded_instance_config {
      enable_secure_boot = true
    }
  }

  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }

  # Enable automatic node upgrades
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_container_cluster.primary]
}

# Create the Kubernetes namespace for our application
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.project_name
  }

  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

# Create a Kubernetes service account for our application
resource "kubernetes_service_account" "app" {
  metadata {
    name      = "${var.project_name}-sa"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.app
  ]
}

# Create a Kubernetes service for the application that integrates with the NEG
resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.project_name}-api-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "cloud.google.com/neg"           = "{\"ingress\":true}"
      "cloud.google.com/neg-status"    = "{\"network_endpoint_groups\": {\"8000\": \"${google_compute_network_endpoint_group.gke_neg.name}\"}}"
      "cloud.google.com/app-protocols" = "{\"http\": \"HTTP\"}"
    }
  }

  spec {
    selector = {
      app = "${var.project_name}-api"
    }

    port {
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }

  depends_on = [
    kubernetes_namespace.app,
    google_compute_network_endpoint_group.gke_neg
  ]
}

# Health check for the backend service
resource "google_compute_health_check" "gke_health_check" {
  name               = "${var.project_name}-gke-health-check"
  timeout_sec        = 5
  check_interval_sec = 10

  http_health_check {
    port         = 8000
    request_path = "/healthz"
  }

  log_config {
    enable = true
  }

  depends_on = [google_project_service.required_services]
}

# Backend service for the GKE cluster
resource "google_compute_backend_service" "gke_backend" {
  name                  = "${var.project_name}-gke-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.gke_health_check.id]
  load_balancing_scheme = "EXTERNAL"

  # Use NEG instead of instance group
  backend {
    group                 = google_compute_network_endpoint_group.gke_neg.id
    balancing_mode        = "RATE"
    max_rate_per_endpoint = 100
  }

  depends_on = [
    google_compute_health_check.gke_health_check,
    google_compute_network_endpoint_group.gke_neg
  ]
}

# Create a Network Endpoint Group (NEG) for the GKE service
resource "google_compute_network_endpoint_group" "gke_neg" {
  name                  = "${var.project_name}-gke-neg"
  network               = google_compute_network.vpc_network.id
  subnetwork            = google_compute_subnetwork.gke_subnet.id
  default_port          = 8000
  zone                  = var.gke_instance_node_zone # Using first zone in the region
  network_endpoint_type = "GCE_VM_IP_PORT"

  depends_on = [
    google_container_node_pool.primary_nodes,
    google_compute_network.vpc_network
  ]
}

# URL map for the load balancer
resource "google_compute_url_map" "url_map" {
  name            = "${var.project_name}-url-map"
  default_service = google_compute_backend_bucket.cdn_backend.id

  # Route api requests to the GKE backend
  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "path-matcher-1"
  }

  path_matcher {
    name            = "path-matcher-1"
    default_service = google_compute_backend_bucket.cdn_backend.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.gke_backend.id
    }
  }

  depends_on = [
    google_compute_backend_bucket.cdn_backend,
    google_compute_backend_service.gke_backend
  ]
}

# HTTPS proxy with custom SSL certificate
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "${var.project_name}-https-proxy"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_ssl_certificate.default.id]

  depends_on = [
    google_compute_url_map.url_map,
    google_compute_ssl_certificate.default
  ]
}

# Reserve a global IP address for the load balancer
resource "google_compute_global_address" "lb_ip" {
  name = "${var.project_name}-lb-ip"

  depends_on = [google_project_service.required_services]
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "https" {
  name       = "${var.project_name}-https-rule"
  target     = google_compute_target_https_proxy.https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.lb_ip.address

  depends_on = [
    google_compute_target_https_proxy.https_proxy,
    google_compute_global_address.lb_ip
  ]
}

# Create a HTTP -> HTTPS redirect
resource "google_compute_url_map" "https_redirect" {
  name = "${var.project_name}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }

  depends_on = [google_project_service.required_services]
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.https_redirect.id

  depends_on = [google_compute_url_map.https_redirect]
}

resource "google_compute_global_forwarding_rule" "http" {
  name       = "${var.project_name}-http-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.lb_ip.address

  depends_on = [
    google_compute_target_http_proxy.http_proxy,
    google_compute_global_address.lb_ip
  ]
}

# Optional: Egress firewall rules for domain-based restrictions
resource "google_compute_firewall" "egress_restrictions" {
  count     = length(var.allowed_egress_domains) > 0 ? 1 : 0
  name      = "${var.project_name}-egress-restrictions"
  network   = google_compute_network.vpc_network.name
  direction = "EGRESS"

  # Deny all outbound traffic by default if domains are specified
  deny {
    protocol = "all"
  }

  # Target all GKE nodes
  target_tags = ["gke-node"]

  # All destinations except allowed ranges (managed through separate allow rule)
  destination_ranges = ["0.0.0.0/0"]

  # Log all denied egress traffic
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_firewall" "egress_allow" {
  count     = length(var.allowed_egress_domains) > 0 ? 1 : 0
  name      = "${var.project_name}-egress-allow"
  network   = google_compute_network.vpc_network.name
  direction = "EGRESS"

  # Allow HTTPS traffic to specific destinations
  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  # Target all GKE nodes
  target_tags = ["gke-node"]

  # Allowed destination ranges (resolved from domain names in allowed_egress_domains)
  destination_ranges = var.allowed_egress_ip_ranges

  # Log all allowed egress traffic
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}

# Create a BigQuery dataset for VPC flow logs
resource "google_bigquery_dataset" "vpc_flow_logs" {
  dataset_id    = "vpc_flow_logs"
  friendly_name = "VPC Flow Logs"
  description   = "VPC Flow Logs for network traffic analysis"
  location      = "US"

  # Set expiration for logs
  default_table_expiration_ms = 2592000000 # 30 days

  # Restrict access to the dataset
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  depends_on = [google_project_service.required_services]
}

# Create a Log Router sink for VPC flow logs
resource "google_logging_project_sink" "vpc_flow_logs" {
  name        = "${var.project_name}-vpc-flow-logs"
  description = "Export all VPC flow logs to BigQuery"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.vpc_flow_logs.dataset_id}"
  filter      = "resource.type=gce_subnetwork AND logName:\"compute.googleapis.com/vpc_flows\""

  unique_writer_identity = true

  depends_on = [google_bigquery_dataset.vpc_flow_logs]
}

# Grant permissions to the Log Router service account
resource "google_project_iam_binding" "bigquery_sink_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"

  members = [
    google_logging_project_sink.vpc_flow_logs.writer_identity,
  ]

  depends_on = [google_logging_project_sink.vpc_flow_logs]
}

# Create an aggregated log sink for HTTP load balancer logs
resource "google_logging_project_sink" "lb_logs" {
  name        = "${var.project_name}-lb-logs"
  description = "Export load balancer logs to storage"
  destination = "storage.googleapis.com/${google_storage_bucket.portfolio_logs_bucket.name}"
  filter      = "resource.type=(http_load_balancer OR https_load_balancer)"

  unique_writer_identity = true

  depends_on = [google_storage_bucket.portfolio_logs_bucket]
}

# Create a separate log sink for backend services (includes CDN)
resource "google_logging_project_sink" "backend_service_logs" {
  name        = "${var.project_name}-backend-logs"
  description = "Export backend services logs (includes CDN)"
  destination = "storage.googleapis.com/${google_storage_bucket.portfolio_logs_bucket.name}"
  filter      = "resource.type=backend_service"

  unique_writer_identity = true

  depends_on = [google_storage_bucket.portfolio_logs_bucket]
}

# Grant permissions to write to the log bucket
resource "google_storage_bucket_iam_binding" "storage_sink_writer" {
  bucket = google_storage_bucket.portfolio_logs_bucket.name
  role   = "roles/storage.objectCreator"

  members = [
    google_logging_project_sink.lb_logs.writer_identity,
    google_logging_project_sink.backend_service_logs.writer_identity,
  ]

  depends_on = [
    google_storage_bucket.portfolio_logs_bucket,
    google_logging_project_sink.lb_logs,
    google_logging_project_sink.backend_service_logs
  ]
}

# Add an explicit IAM binding for the load balancer log sink
resource "google_storage_bucket_iam_member" "lb_logs_writer" {
  bucket = google_storage_bucket.portfolio_logs_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.lb_logs.writer_identity

  depends_on = [
    google_storage_bucket.portfolio_logs_bucket,
    google_logging_project_sink.lb_logs
  ]
}

# DNS CONFIGURATION (SIMPLIFIED)

# Create the DNS zone if it doesn't exist
resource "google_dns_managed_zone" "dns_zone" {
  count       = var.dns_zone_name != "" ? 1 : 0
  name        = var.dns_zone_name
  dns_name    = "${var.domain_name}."
  description = "DNS zone for ${var.domain_name}"

  depends_on = [google_project_service.required_services]
}

# Root domain A record automatically pointing to load balancer IP
resource "google_dns_record_set" "root_domain" {
  count = var.dns_zone_name != "" ? 1 : 0

  name         = "${var.domain_name}."
  managed_zone = var.dns_zone_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]

  depends_on = [
    google_dns_managed_zone.dns_zone,
    google_compute_global_address.lb_ip
  ]
}

# All other DNS records from the dns_records map variable
resource "google_dns_record_set" "dns_records" {
  for_each = var.dns_records

  name         = "${each.key}.${var.domain_name}."
  managed_zone = var.dns_zone_name != "" ? var.dns_zone_name : each.value.zone_name
  type         = each.value.record_type
  ttl          = each.value.ttl
  rrdatas      = each.value.records

  depends_on = [
    google_dns_managed_zone.dns_zone
  ]
}

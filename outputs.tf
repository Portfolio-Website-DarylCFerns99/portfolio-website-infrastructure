# output "neg_info" {
#   value       = "NEG name: ${data.google_compute_network_endpoint_group.auto_neg.name}, Network: ${data.google_compute_network_endpoint_group.auto_neg.network}, Port: ${data.google_compute_network_endpoint_group.auto_neg.default_port}"
#   description = "Information about the Network Endpoint Group"
# } # Output variables from the Terraform deployment

output "load_balancer_ip" {
  value       = google_compute_global_address.lb_ip.address
  description = "The IP address of the load balancer, use this for DNS configuration"
}

output "frontend_bucket_name" {
  value       = google_storage_bucket.frontend_bucket.name
  description = "The name of the storage bucket for frontend assets"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "The name of the GKE cluster"
}

output "kubectl_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.gke_type == "region" ? var.region : var.gke_instance_node_zone} --project ${var.project_id}"
  description = "Command to get GKE cluster credentials"
}

output "frontend_url" {
  value       = "https://${var.domain_name}"
  description = "The URL to access the frontend"
}

output "api_url" {
  value       = "https://${var.domain_name}/api"
  description = "The URL to access the API"
}

output "dns_configuration" {
  value       = "Create an A record for ${var.domain_name} pointing to ${google_compute_global_address.lb_ip.address}"
  description = "Instructions for DNS configuration"
}

output "enabled_apis" {
  value       = [for s in google_project_service.required_services : s.service]
  description = "List of enabled GCP APIs"
}

output "namespace" {
  value       = kubernetes_namespace.app.metadata[0].name
  description = "Kubernetes namespace for the application"
}

output "deployment_name" {
  value       = "${var.project_name}-api"
  description = "Suggested Kubernetes deployment name for the backend"
}

# DNS-related outputs
output "dns_zone_name" {
  value       = var.dns_zone_name != "" && length(google_dns_managed_zone.dns_zone) > 0 ? google_dns_managed_zone.dns_zone[0].name : "None (using external DNS)"
  description = "The name of the DNS zone"
}

output "dns_nameservers" {
  value       = var.dns_zone_name != "" && length(google_dns_managed_zone.dns_zone) > 0 ? google_dns_managed_zone.dns_zone[0].name_servers : []
  description = "The nameservers for the DNS zone (if created)"
}

output "root_domain_record" {
  value       = var.dns_zone_name != "" && length(google_dns_record_set.root_domain) > 0 ? "A record for ${var.domain_name} → ${google_compute_global_address.lb_ip.address}" : "None (using external DNS)"
  description = "Root domain DNS record"
}

output "dns_records_summary" {
  value       = { for k, v in var.dns_records : k => "${v.record_type} record pointing to ${join(", ", v.records)}" }
  description = "Summary of all configured DNS records"
}

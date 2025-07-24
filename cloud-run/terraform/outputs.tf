# MetaMCP Terraform Outputs
# Define outputs for important resource information

# Cloud Run Service URLs
output "frontend_url" {
  description = "URL of the frontend Cloud Run service"
  value       = google_cloud_run_service.frontend.status[0].url
}

output "backend_url" {
  description = "URL of the backend Cloud Run service"
  value       = google_cloud_run_service.backend.status[0].url
}

# Service Names
output "frontend_service_name" {
  description = "Name of the frontend Cloud Run service"
  value       = google_cloud_run_service.frontend.name
}

output "backend_service_name" {
  description = "Name of the backend Cloud Run service"
  value       = google_cloud_run_service.backend.name
}

# Database Information
output "database_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.main.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_name" {
  description = "Name of the database"
  value       = google_sql_database.main.name
}

# Service Account Information
output "frontend_service_account_email" {
  description = "Email of the frontend service account"
  value       = var.create_service_accounts ? google_service_account.frontend[0].email : null
}

output "backend_service_account_email" {
  description = "Email of the backend service account"
  value       = var.create_service_accounts ? google_service_account.backend[0].email : null
}

# Network Information
output "vpc_name" {
  description = "Name of the VPC"
  value       = var.create_vpc ? google_compute_network.main[0].name : var.vpc_name
}

output "vpc_connector_name" {
  description = "Name of the VPC connector"
  value       = var.create_vpc_connector ? google_vpc_access_connector.main[0].name : null
}

# Redis Information
output "redis_host" {
  description = "Redis instance host"
  value       = var.enable_redis ? google_redis_instance.main[0].host : null
}

output "redis_port" {
  description = "Redis instance port"
  value       = var.enable_redis ? google_redis_instance.main[0].port : null
}

# Project Information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

# Secret Manager Secrets
output "secret_names" {
  description = "List of created Secret Manager secret names"
  value       = [for secret in google_secret_manager_secret.secrets : secret.name]
}

# Load Balancer Information (if custom domain is configured)
output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = var.domain_name != "" ? google_compute_global_address.main[0].address : null
}

# Monitoring Information
output "log_sink_name" {
  description = "Name of the Cloud Logging sink"
  value       = var.enable_monitoring ? google_logging_project_sink.main[0].name : null
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    frontend_url             = google_cloud_run_service.frontend.status[0].url
    backend_url              = google_cloud_run_service.backend.status[0].url
    database_connection_name = google_sql_database_instance.main.connection_name
    redis_enabled           = var.enable_redis
    custom_domain           = var.domain_name
    environment             = var.environment
    region                  = var.region
  }
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for application configuration"
  value = {
    database = {
      host             = "/cloudsql/${google_sql_database_instance.main.connection_name}"
      name             = google_sql_database.main.name
      user             = google_sql_user.main.name
      connection_name  = google_sql_database_instance.main.connection_name
      private_ip       = google_sql_database_instance.main.private_ip_address
    }
    redis = var.enable_redis ? {
      host = google_redis_instance.main[0].host
      port = google_redis_instance.main[0].port
      url  = "redis://${google_redis_instance.main[0].host}:${google_redis_instance.main[0].port}"
    } : null
    frontend = {
      service_name = google_cloud_run_service.frontend.name
      url          = google_cloud_run_service.frontend.status[0].url
    }
    backend = {
      service_name = google_cloud_run_service.backend.name
      url          = google_cloud_run_service.backend.status[0].url
    }
  }
  sensitive = false
}
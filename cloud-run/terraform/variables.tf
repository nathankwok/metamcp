# MetaMCP Terraform Variables
# Define all variables used in the Terraform configuration

# Core Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "development", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, development, staging, prod, production."
  }
}

variable "service_prefix" {
  description = "Prefix for service names"
  type        = string
  default     = "metamcp"
}

# Cloud Run Configuration
variable "frontend_image" {
  description = "Docker image for frontend service"
  type        = string
  default     = "gcr.io/PROJECT_ID/metamcp-frontend:latest"
}

variable "backend_image" {
  description = "Docker image for backend service"
  type        = string
  default     = "gcr.io/PROJECT_ID/metamcp-backend:latest"
}

variable "frontend_cpu" {
  description = "CPU allocation for frontend service"
  type        = string
  default     = "1000m"
}

variable "frontend_memory" {
  description = "Memory allocation for frontend service"
  type        = string
  default     = "1Gi"
}

variable "backend_cpu" {
  description = "CPU allocation for backend service"
  type        = string
  default     = "2000m"
}

variable "backend_memory" {
  description = "Memory allocation for backend service"
  type        = string
  default     = "2Gi"
}

variable "frontend_min_instances" {
  description = "Minimum number of frontend instances"
  type        = number
  default     = 0
}

variable "frontend_max_instances" {
  description = "Maximum number of frontend instances"
  type        = number
  default     = 50
}

variable "backend_min_instances" {
  description = "Minimum number of backend instances"
  type        = number
  default     = 0
}

variable "backend_max_instances" {
  description = "Maximum number of backend instances"
  type        = number
  default     = 100
}

variable "frontend_concurrency" {
  description = "Maximum concurrent requests per frontend instance"
  type        = number
  default     = 100
}

variable "backend_concurrency" {
  description = "Maximum concurrent requests per backend instance"
  type        = number
  default     = 80
}

# Database Configuration
variable "database_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"
}

variable "database_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 20
}

variable "database_disk_type" {
  description = "Cloud SQL disk type"
  type        = string
  default     = "PD_SSD"
}

variable "database_backup_enabled" {
  description = "Enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "database_backup_start_time" {
  description = "Backup start time in HH:MM format"
  type        = string
  default     = "03:00"
}

variable "database_maintenance_window_day" {
  description = "Maintenance window day (1-7, Sunday = 1)"
  type        = number
  default     = 1
}

variable "database_maintenance_window_hour" {
  description = "Maintenance window hour (0-23)"
  type        = number
  default     = 4
}

# Networking Configuration
variable "create_vpc" {
  description = "Whether to create a new VPC"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC (existing or to be created)"
  type        = string
  default     = ""
}

variable "create_vpc_connector" {
  description = "Whether to create a VPC connector for Cloud Run"
  type        = bool
  default     = true
}

variable "vpc_connector_cidr" {
  description = "CIDR range for VPC connector"
  type        = string
  default     = "10.8.0.0/28"
}

# Redis Configuration
variable "enable_redis" {
  description = "Whether to create a Redis instance"
  type        = bool
  default     = true
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}

variable "redis_tier" {
  description = "Redis service tier"
  type        = string
  default     = "BASIC"
  
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either BASIC or STANDARD_HA."
  }
}

# Security Configuration
variable "database_require_ssl" {
  description = "Require SSL for database connections"
  type        = bool
  default     = true
}

variable "enable_private_ip" {
  description = "Enable private IP for Cloud SQL"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Custom Domain Configuration
variable "domain_name" {
  description = "Custom domain name for the frontend service"
  type        = string
  default     = ""
}

variable "ssl_certificate_name" {
  description = "Name of the SSL certificate for custom domain"
  type        = string
  default     = ""
}

# Service Account Configuration
variable "create_service_accounts" {
  description = "Whether to create service accounts for Cloud Run services"
  type        = bool
  default     = true
}

# Secret Manager Configuration
variable "secrets" {
  description = "Map of secrets to create in Secret Manager"
  type = map(object({
    secret_data = string
  }))
  default = {}
  sensitive = true
}

# Labels and Tags
variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for DDoS protection"
  type        = bool
  default     = false
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for frontend"
  type        = bool
  default     = false
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy"
  type        = bool
  default     = false
}
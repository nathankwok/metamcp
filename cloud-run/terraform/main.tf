# MetaMCP Cloud Run Infrastructure
# Main Terraform configuration for deploying MetaMCP to Google Cloud Run

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "metamcp/terraform/state"
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Data sources
data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "redis.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com"
  ])

  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Local values for common configurations
locals {
  common_labels = {
    project     = "metamcp"
    environment = var.environment
    managed_by  = "terraform"
  }

  service_labels = merge(local.common_labels, {
    component = "cloud-run"
  })

  database_labels = merge(local.common_labels, {
    component = "database"
  })

  frontend_service_name = "${var.service_prefix}-frontend"
  backend_service_name  = "${var.service_prefix}-backend"
  
  # Cloud SQL instance name
  sql_instance_name = "${var.service_prefix}-db-${var.environment}"
  
  # Database configuration
  database_name = "metamcp_${var.environment}"
  database_user = "metamcp_user"
}
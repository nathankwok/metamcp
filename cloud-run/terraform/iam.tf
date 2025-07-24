# IAM Configuration for MetaMCP Cloud Run Services
# Service accounts, roles, and permissions

# Service account for the frontend Cloud Run service
resource "google_service_account" "frontend" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "${var.service_prefix}-frontend-${var.environment}"
  display_name = "MetaMCP Frontend Service Account"
  description  = "Service account for MetaMCP frontend Cloud Run service"

  depends_on = [google_project_service.apis]
}

# Service account for the backend Cloud Run service
resource "google_service_account" "backend" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "${var.service_prefix}-backend-${var.environment}"
  display_name = "MetaMCP Backend Service Account"
  description  = "Service account for MetaMCP backend Cloud Run service"

  depends_on = [google_project_service.apis]
}

# IAM roles for the backend service account
resource "google_project_iam_member" "backend_sql_client" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

resource "google_project_iam_member" "backend_secret_accessor" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

resource "google_project_iam_member" "backend_logging_writer" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

resource "google_project_iam_member" "backend_monitoring_writer" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

resource "google_project_iam_member" "backend_trace_agent" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

# Redis access for backend (if Redis is enabled)
resource "google_project_iam_member" "backend_redis_editor" {
  count   = var.create_service_accounts && var.enable_redis ? 1 : 0
  project = var.project_id
  role    = "roles/redis.editor"
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

# IAM roles for the frontend service account
resource "google_project_iam_member" "frontend_logging_writer" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.frontend[0].email}"
}

resource "google_project_iam_member" "frontend_monitoring_writer" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.frontend[0].email}"
}

resource "google_project_iam_member" "frontend_trace_agent" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.frontend[0].email}"
}

# Allow backend service account to invoke frontend service (for server-side rendering if needed)
resource "google_cloud_run_service_iam_member" "backend_to_frontend" {
  count    = var.create_service_accounts ? 1 : 0
  location = google_cloud_run_service.frontend.location
  project  = google_cloud_run_service.frontend.project
  service  = google_cloud_run_service.frontend.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend[0].email}"
}

# Allow frontend service account to invoke backend service
resource "google_cloud_run_service_iam_member" "frontend_to_backend" {
  count    = var.create_service_accounts ? 1 : 0
  location = google_cloud_run_service.backend.location
  project  = google_cloud_run_service.backend.project
  service  = google_cloud_run_service.backend.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.frontend[0].email}"
}

# Service account for Cloud Build (if needed for automated deployments)
resource "google_service_account" "cloudbuild" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "${var.service_prefix}-cloudbuild-${var.environment}"
  display_name = "MetaMCP Cloud Build Service Account"
  description  = "Service account for MetaMCP Cloud Build deployments"

  depends_on = [google_project_service.apis]
}

# IAM roles for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_run_admin" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild[0].email}"
}

resource "google_project_iam_member" "cloudbuild_service_account_user" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild[0].email}"
}

resource "google_project_iam_member" "cloudbuild_storage_admin" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild[0].email}"
}

# Custom IAM role for MCP server management (backend specific permissions)
resource "google_project_iam_custom_role" "mcp_server_manager" {
  role_id     = "${var.service_prefix}_mcp_server_manager_${var.environment}"
  title       = "MCP Server Manager"
  description = "Custom role for managing MCP servers in MetaMCP backend"
  permissions = [
    "compute.instances.get",
    "compute.instances.list",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
    "secretmanager.versions.access",
    "run.services.get",
    "run.services.list",
    "monitoring.metricDescriptors.create",
    "monitoring.metricDescriptors.get",
    "monitoring.metricDescriptors.list",
    "monitoring.timeSeries.create"
  ]
}

# Assign custom role to backend service account
resource "google_project_iam_member" "backend_mcp_manager" {
  count   = var.create_service_accounts ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.mcp_server_manager.name
  member  = "serviceAccount:${google_service_account.backend[0].email}"
}

# Storage bucket for MCP server data (if needed)
resource "google_storage_bucket" "mcp_data" {
  name          = "${var.project_id}-${var.service_prefix}-mcp-data-${var.environment}"
  location      = var.region
  force_destroy = var.environment != "production"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

# IAM for storage bucket
resource "google_storage_bucket_iam_member" "backend_storage_admin" {
  count  = var.create_service_accounts ? 1 : 0
  bucket = google_storage_bucket.mcp_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend[0].email}"
}

# Workload Identity (if using GKE in the future)
resource "google_service_account_iam_member" "workload_identity_frontend" {
  count              = var.create_service_accounts ? 1 : 0
  service_account_id = google_service_account.frontend[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/metamcp-frontend]"
}

resource "google_service_account_iam_member" "workload_identity_backend" {
  count              = var.create_service_accounts ? 1 : 0
  service_account_id = google_service_account.backend[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/metamcp-backend]"
}
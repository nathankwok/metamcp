# Cloud Run Services Configuration for MetaMCP
# Frontend and Backend Cloud Run services

# Backend Cloud Run Service
resource "google_cloud_run_service" "backend" {
  name     = local.backend_service_name
  location = var.region

  template {
    metadata {
      labels = local.service_labels
      annotations = {
        "autoscaling.knative.dev/minScale"      = tostring(var.backend_min_instances)
        "autoscaling.knative.dev/maxScale"      = tostring(var.backend_max_instances)
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.main.connection_name
        "run.googleapis.com/vpc-access-connector" = var.create_vpc_connector ? google_vpc_access_connector.main[0].name : null
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }

    spec {
      container_concurrency = var.backend_concurrency
      timeout_seconds      = 3600
      service_account_name = var.create_service_accounts ? google_service_account.backend[0].email : null

      containers {
        image = replace(var.backend_image, "PROJECT_ID", var.project_id)

        ports {
          container_port = 8080
        }

        resources {
          limits = {
            cpu    = var.backend_cpu
            memory = var.backend_memory
          }
        }

        env {
          name  = "NODE_ENV"
          value = var.environment == "production" ? "production" : "development"
        }

        env {
          name  = "PORT"
          value = "8080"
        }

        env {
          name  = "DB_HOST"
          value = "/cloudsql/${google_sql_database_instance.main.connection_name}"
        }

        env {
          name  = "DB_NAME"
          value = google_sql_database.main.name
        }

        env {
          name  = "DB_USER"
          value = google_sql_user.main.name
        }

        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_password.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "DATABASE_URL"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.database_url.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "BETTER_AUTH_SECRET"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.better_auth_secret.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name  = "BETTER_AUTH_URL"
          value = "https://${local.backend_service_name}-${random_id.service_suffix.hex}-${substr(var.region, 0, 2)}.a.run.app"
        }

        dynamic "env" {
          for_each = var.enable_redis ? [1] : []
          content {
            name  = "REDIS_URL"
            value = local.redis_url
          }
        }

        env {
          name  = "LOG_LEVEL"
          value = var.environment == "production" ? "info" : "debug"
        }

        env {
          name  = "ENABLE_REQUEST_LOGGING"
          value = "true"
        }

        env {
          name  = "ENABLE_METRICS"
          value = "true"
        }

        env {
          name  = "ENABLE_TRACING"
          value = var.environment == "production" ? "true" : "false"
        }

        # Health check probe
        startup_probe {
          http_get {
            path = "/api/health"
            port = 8080
          }
          initial_delay_seconds = 30
          timeout_seconds      = 5
          period_seconds       = 10
          failure_threshold    = 3
        }

        liveness_probe {
          http_get {
            path = "/api/health"
            port = 8080
          }
          initial_delay_seconds = 60
          timeout_seconds      = 5
          period_seconds       = 30
          failure_threshold    = 3
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.apis,
    google_sql_database_instance.main,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.better_auth_secret
  ]
}

# Frontend Cloud Run Service
resource "google_cloud_run_service" "frontend" {
  name     = local.frontend_service_name
  location = var.region

  template {
    metadata {
      labels = local.service_labels
      annotations = {
        "autoscaling.knative.dev/minScale" = tostring(var.frontend_min_instances)
        "autoscaling.knative.dev/maxScale" = tostring(var.frontend_max_instances)
      }
    }

    spec {
      container_concurrency = var.frontend_concurrency
      timeout_seconds      = 300
      service_account_name = var.create_service_accounts ? google_service_account.frontend[0].email : null

      containers {
        image = replace(var.frontend_image, "PROJECT_ID", var.project_id)

        ports {
          container_port = 8080
        }

        resources {
          limits = {
            cpu    = var.frontend_cpu
            memory = var.frontend_memory
          }
        }

        env {
          name  = "NODE_ENV"
          value = var.environment == "production" ? "production" : "development"
        }

        env {
          name  = "PORT"
          value = "8080"
        }

        env {
          name  = "NEXT_PUBLIC_BACKEND_URL"
          value = google_cloud_run_service.backend.status[0].url
        }

        env {
          name  = "NEXT_PUBLIC_APP_NAME"
          value = "MetaMCP"
        }

        env {
          name  = "NEXT_PUBLIC_APP_VERSION"
          value = var.environment == "production" ? "1.0.0" : "dev"
        }

        env {
          name  = "NEXT_PUBLIC_ENABLE_ANALYTICS"
          value = var.environment == "production" ? "true" : "false"
        }

        env {
          name  = "NEXT_PUBLIC_DEBUG_MODE"
          value = var.environment == "production" ? "false" : "true"
        }

        env {
          name  = "NEXT_PUBLIC_ENABLE_MCP_INSPECTOR"
          value = var.environment == "production" ? "false" : "true"
        }

        env {
          name  = "NEXT_PUBLIC_ENABLE_MIDDLEWARE_DEBUG"
          value = var.environment == "production" ? "false" : "true"
        }

        env {
          name  = "NEXT_PUBLIC_ENABLE_PERFORMANCE_MONITORING"
          value = var.environment == "production" ? "true" : "false"
        }

        env {
          name  = "NEXT_TELEMETRY_DISABLED"
          value = "1"
        }

        # Health check probe
        startup_probe {
          http_get {
            path = "/api/health"
            port = 8080
          }
          initial_delay_seconds = 30
          timeout_seconds      = 5
          period_seconds       = 10
          failure_threshold    = 3
        }

        liveness_probe {
          http_get {
            path = "/api/health"
            port = 8080
          }
          initial_delay_seconds = 60
          timeout_seconds      = 5
          period_seconds       = 30
          failure_threshold    = 3
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.apis,
    google_cloud_run_service.backend
  ]
}

# IAM policy for Cloud Run services (allow unauthenticated access)
resource "google_cloud_run_service_iam_member" "frontend_public" {
  location = google_cloud_run_service.frontend.location
  project  = google_cloud_run_service.frontend.project
  service  = google_cloud_run_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "backend_public" {
  location = google_cloud_run_service.backend.location
  project  = google_cloud_run_service.backend.project
  service  = google_cloud_run_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Random suffix for service URLs
resource "random_id" "service_suffix" {
  byte_length = 4
}

# Better Auth Secret
resource "random_password" "better_auth_secret" {
  length  = 64
  special = true
}

resource "google_secret_manager_secret" "better_auth_secret" {
  secret_id = "${var.service_prefix}-better-auth-secret-${var.environment}"
  labels    = local.service_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "better_auth_secret" {
  secret      = google_secret_manager_secret.better_auth_secret.id
  secret_data = random_password.better_auth_secret.result
}
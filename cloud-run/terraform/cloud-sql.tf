# Cloud SQL Configuration for MetaMCP
# PostgreSQL database instance and related resources

# Random password for database user
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store database password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.service_prefix}-db-password-${var.environment}"
  labels    = local.database_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "main" {
  name             = local.sql_instance_name
  database_version = "POSTGRES_16"
  region           = var.region
  deletion_protection = var.environment == "production" ? true : false

  settings {
    tier                        = var.database_tier
    availability_type          = var.environment == "production" ? "REGIONAL" : "ZONAL"
    disk_size                  = var.database_disk_size
    disk_type                  = var.database_disk_type
    disk_autoresize            = true
    disk_autoresize_limit      = var.database_disk_size * 4

    backup_configuration {
      enabled                        = var.database_backup_enabled
      start_time                     = var.database_backup_start_time
      location                       = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.database_maintenance_window_day
      hour         = var.database_maintenance_window_hour
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled                                  = !var.enable_private_ip
      private_network                               = var.create_vpc ? google_compute_network.main[0].id : data.google_compute_network.existing[0].id
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = var.database_require_ssl

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_statement"
      value = "ddl"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
    }
  }

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection
  ]

  labels = local.database_labels
}

# Database
resource "google_sql_database" "main" {
  name     = local.database_name
  instance = google_sql_database_instance.main.name
}

# Database user
resource "google_sql_user" "main" {
  name     = local.database_user
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# IAM database user for Cloud Run service accounts (optional)
resource "google_sql_user" "backend_iam" {
  count    = var.create_service_accounts ? 1 : 0
  name     = google_service_account.backend[0].email
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Redis instance for caching (optional)
resource "google_redis_instance" "main" {
  count           = var.enable_redis ? 1 : 0
  name            = "${var.service_prefix}-redis-${var.environment}"
  tier            = var.redis_tier
  memory_size_gb  = var.redis_memory_size_gb
  region          = var.region
  location_id     = "${var.region}-a"

  authorized_network = var.create_vpc ? google_compute_network.main[0].id : data.google_compute_network.existing[0].id

  redis_version     = "REDIS_7_0"
  display_name      = "MetaMCP Redis Cache"
  reserved_ip_range = "10.36.0.0/29"

  labels = local.database_labels

  provisioned_throughput = var.redis_tier == "STANDARD_HA" ? {
    read_throughput_mb  = 1000
    write_throughput_mb = 1000
  } : null

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Output database connection string for applications
locals {
  database_url = "postgresql://${google_sql_user.main.name}:${random_password.db_password.result}@/${google_sql_database.main.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
  
  redis_url = var.enable_redis ? "redis://${google_redis_instance.main[0].host}:${google_redis_instance.main[0].port}" : null
}

# Store database URL in Secret Manager
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.service_prefix}-database-url-${var.environment}"
  labels    = local.database_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = local.database_url
}
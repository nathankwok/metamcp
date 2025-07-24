# Networking Configuration for MetaMCP Cloud Run Services
# VPC, subnets, VPC connector, and networking resources

# Create VPC network (optional)
resource "google_compute_network" "main" {
  count                   = var.create_vpc ? 1 : 0
  name                    = var.vpc_name != "" ? var.vpc_name : "${var.service_prefix}-vpc-${var.environment}"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"

  depends_on = [google_project_service.apis]
}

# Get existing VPC if not creating new one
data "google_compute_network" "existing" {
  count = var.create_vpc ? 0 : 1
  name  = var.vpc_name
}

# Private subnet for database and Redis
resource "google_compute_subnetwork" "private" {
  count         = var.create_vpc ? 1 : 0
  name          = "${var.service_prefix}-private-subnet-${var.environment}"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.main[0].id
  region        = var.region

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.0.16.0/20"
  }
}

# Reserved IP range for private services (Cloud SQL, Redis)
resource "google_compute_global_address" "private_services" {
  count         = var.create_vpc ? 1 : 0
  name          = "${var.service_prefix}-private-services-${var.environment}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main[0].id

  depends_on = [google_project_service.apis]
}

# Private connection for managed services
resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.create_vpc ? 1 : 0
  network                 = google_compute_network.main[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services[0].name]

  depends_on = [google_project_service.apis]
}

# VPC Connector for Cloud Run to access VPC resources
resource "google_vpc_access_connector" "main" {
  count          = var.create_vpc_connector ? 1 : 0
  name           = "${var.service_prefix}-vpc-connector-${var.environment}"
  region         = var.region
  ip_cidr_range  = var.vpc_connector_cidr
  network        = var.create_vpc ? google_compute_network.main[0].name : var.vpc_name
  max_throughput = 1000
  min_throughput = 200

  depends_on = [
    google_project_service.apis,
    google_compute_subnetwork.private
  ]
}

# Firewall rules for VPC
resource "google_compute_firewall" "allow_internal" {
  count   = var.create_vpc ? 1 : 0
  name    = "${var.service_prefix}-allow-internal-${var.environment}"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16"
  ]

  target_tags = ["${var.service_prefix}-internal"]
}

# Firewall rule for VPC connector
resource "google_compute_firewall" "allow_vpc_connector" {
  count   = var.create_vpc && var.create_vpc_connector ? 1 : 0
  name    = "${var.service_prefix}-allow-vpc-connector-${var.environment}"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["667"]
  }

  allow {
    protocol = "udp"
    ports    = ["665-666"]
  }

  source_ranges = [var.vpc_connector_cidr]
  target_tags   = ["vpc-connector"]
}

# Firewall rule for Cloud SQL
resource "google_compute_firewall" "allow_cloud_sql" {
  count   = var.create_vpc ? 1 : 0
  name    = "${var.service_prefix}-allow-cloud-sql-${var.environment}"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = [
    google_compute_subnetwork.private[0].ip_cidr_range,
    var.vpc_connector_cidr
  ]

  target_tags = ["cloud-sql"]
}

# Firewall rule for Redis
resource "google_compute_firewall" "allow_redis" {
  count   = var.create_vpc && var.enable_redis ? 1 : 0
  name    = "${var.service_prefix}-allow-redis-${var.environment}"
  network = google_compute_network.main[0].name

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  source_ranges = [
    google_compute_subnetwork.private[0].ip_cidr_range,
    var.vpc_connector_cidr
  ]

  target_tags = ["redis"]
}

# NAT Gateway for outbound internet access (optional)
resource "google_compute_router" "main" {
  count   = var.create_vpc ? 1 : 0
  name    = "${var.service_prefix}-router-${var.environment}"
  region  = var.region
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "main" {
  count                              = var.create_vpc ? 1 : 0
  name                               = "${var.service_prefix}-nat-${var.environment}"
  router                             = google_compute_router.main[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Global IP address for custom domain (if needed)
resource "google_compute_global_address" "main" {
  count        = var.domain_name != "" ? 1 : 0
  name         = "${var.service_prefix}-global-ip-${var.environment}"
  address_type = "EXTERNAL"
}

# Load balancer for custom domain (if needed)
resource "google_compute_url_map" "main" {
  count           = var.domain_name != "" ? 1 : 0
  name            = "${var.service_prefix}-url-map-${var.environment}"
  default_service = google_compute_backend_service.frontend[0].id
}

resource "google_compute_backend_service" "frontend" {
  count                           = var.domain_name != "" ? 1 : 0
  name                            = "${var.service_prefix}-frontend-backend-${var.environment}"
  load_balancing_scheme          = "EXTERNAL_MANAGED"
  protocol                       = "HTTP"
  port_name                      = "http"
  timeout_sec                    = 30
  connection_draining_timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.frontend[0].id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_region_network_endpoint_group" "frontend" {
  count                 = var.domain_name != "" ? 1 : 0
  name                  = "${var.service_prefix}-frontend-neg-${var.environment}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.frontend.name
  }
}

resource "google_compute_target_https_proxy" "main" {
  count   = var.domain_name != "" ? 1 : 0
  name    = "${var.service_prefix}-https-proxy-${var.environment}"
  url_map = google_compute_url_map.main[0].id
  ssl_certificates = [var.ssl_certificate_name]
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain_name != "" ? 1 : 0
  name                  = "${var.service_prefix}-https-forwarding-${var.environment}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.main[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.main[0].address
}

resource "google_compute_target_http_proxy" "main" {
  count   = var.domain_name != "" ? 1 : 0
  name    = "${var.service_prefix}-http-proxy-${var.environment}"
  url_map = google_compute_url_map.redirect_https[0].id
}

resource "google_compute_url_map" "redirect_https" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.service_prefix}-redirect-https-${var.environment}"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_global_forwarding_rule" "http" {
  count                 = var.domain_name != "" ? 1 : 0
  name                  = "${var.service_prefix}-http-forwarding-${var.environment}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.main[0].id
  port_range            = "80"
  ip_address            = google_compute_global_address.main[0].address
}

# Security Policy (if Cloud Armor is enabled)
resource "google_compute_security_policy" "main" {
  count       = var.enable_cloud_armor ? 1 : 0
  name        = "${var.service_prefix}-security-policy-${var.environment}"
  description = "Security policy for MetaMCP"

  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Allow all by default"
  }

  rule {
    action   = "deny(403)"
    priority = "2000"
    match {
      expr {
        expression = "origin.region_code == 'CN'"
      }
    }
    description = "Block traffic from China"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}
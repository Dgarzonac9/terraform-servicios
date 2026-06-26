terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name                    = "proyecto-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "proyecto-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-web"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "allow-lb-health-check"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]
}

resource "google_compute_router" "router" {
  name    = "proyecto-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "proyecto-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance" "primary" {
  name         = "vm-servicio-principal"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["web-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = "#!/bin/bash\napt-get update -y\napt-get install -y nginx\nsystemctl enable nginx\nsystemctl start nginx\npython3 -c \"open('/var/www/html/index.html','w').write('<html><body style=background:#e8f5e9><div style=margin:auto;margin-top:20%;text-align:center><h1>Bienvenido al Servicio Principal - Version Produccion</h1></div></body></html>')\"\nsystemctl restart nginx"
}

resource "google_compute_instance" "contingency" {
  name         = "vm-servicio-contingencia"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["web-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = "#!/bin/bash\napt-get update -y\napt-get install -y nginx\nsystemctl enable nginx\nsystemctl start nginx\npython3 -c \"open('/var/www/html/index.html','w').write('<html><body style=background:#fce4ec><div style=margin:auto;margin-top:20%;text-align:center><h1>Error 503 - Sitio en Mantenimiento Programado</h1></div></body></html>')\"\nsystemctl restart nginx"
}

resource "google_compute_instance_group" "primary_group" {
  name      = "grupo-principal"
  zone      = var.zone
  instances = [google_compute_instance.primary.id]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "contingency_group" {
  name      = "grupo-contingencia"
  zone      = var.zone
  instances = [google_compute_instance.contingency.id]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "http_hc" {
  name = "health-check-http"

  http_health_check {
    port         = 80
    request_path = "/"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

resource "google_compute_backend_service" "primary_backend" {
  name                  = "backend-principal"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.http_hc.id]

  backend {
    group           = google_compute_instance_group.primary_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_backend_service" "contingency_backend" {
  name                  = "backend-contingencia"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.http_hc.id]

  backend {
    group           = google_compute_instance_group.contingency_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "url_map" {
  name = "mapa-trafico-url"

  default_route_action {
    weighted_backend_services {
      backend_service = google_compute_backend_service.primary_backend.id
      weight          = var.primary_weight
    }
    weighted_backend_services {
      backend_service = google_compute_backend_service.contingency_backend.id
      weight          = var.contingency_weight
    }
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "proxy-http"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  name                  = "regla-reenvio-http"
  target                = google_compute_target_http_proxy.http_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
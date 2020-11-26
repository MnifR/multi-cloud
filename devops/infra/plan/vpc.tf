resource "google_compute_network" "vpc" {  
  name                    = "vpc"
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.service]
}

resource "google_compute_subnetwork" "subnet-vpc" {
  name                     = "subnet"
  ip_cidr_range            = var.subnet_ip_range_primary
  region                   = var.region
  network                  = google_compute_network.vpc.id
  project                  = var.project_id
  secondary_ip_range       = [
    {
        range_name    = "secondary-ip-ranges-devops-services"
        ip_cidr_range = var.subnet_secondary_ip_range_services
    },
    {
        range_name    = "secondary-ip-ranges-devops-pods"
        ip_cidr_range = var.subnet_secondary_ip_range_pods
    }
  ]
  private_ip_google_access = false
}

# Create an external NAT IP
resource "google_compute_address" "nat" {
  count   = 2
  name    = "nat-external-${count.index}"
  project = var.project_id
  region  = var.region

  depends_on = [google_project_service.service]
}

# Create a NAT router so the nodes can reach DockerHub, etc
resource "google_compute_router" "router" {
  name    = "router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.self_link

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name    = "nat-1"
  project = var.project_id
  router  = google_compute_router.router.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.nat.*.self_link

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet-vpc.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      google_compute_subnetwork.subnet-vpc.secondary_ip_range[0].range_name,
      google_compute_subnetwork.subnet-vpc.secondary_ip_range[1].range_name,
    ]
  }
}

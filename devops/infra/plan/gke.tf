resource "google_container_cluster" "gke-devops-cluster" {
  provider = google-beta

  name = "gke-cluster-devops"
  location = var.gke_devops_cluster_location

  network = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet-vpc.id

  # Configuration for private clusters, clusters with private nodes
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes = true
    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  project = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count = 1

  maintenance_policy {
    recurring_window {
      start_time = "2020-10-01T09:00:00-04:00"
      end_time = "2050-10-01T17:00:00-04:00"
      recurrence = "FREQ=WEEKLY"
    }
  }

  # Enable Shielded Nodes features on all nodes in this cluster
  enable_shielded_nodes = true

  # Configuration of cluster IP allocation for VPC-native clusters
  ip_allocation_policy {
    cluster_secondary_range_name = "secondary-ip-ranges-devops-pods"
    services_secondary_range_name = "secondary-ip-ranges-devops-services"
  }

  # Determines whether alias IPs or routes will be used for pod IPs in the cluster.
  networking_mode = "VPC_NATIVE"

  # The logging service that the cluster should write logs to
  logging_service = "logging.googleapis.com/kubernetes"

  # The monitoring service that the cluster should write metrics to
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # The desired configuration options for master authorized networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = var.gitlab_public_ip_ranges
      display_name = "GITLAB PUBLIC IP RANGES"
    }
    cidr_blocks {
      cidr_block = var.authorized_source_ranges
      display_name = "Authorized IPs"
    }
    cidr_blocks {
      cidr_block = "${google_compute_address.nat[0].address}/32"
      display_name = "NAT IP 1"
    }
    cidr_blocks {
      cidr_block = "${google_compute_address.nat[1].address}/32"
      display_name = "NAT IP 2"
    }
  }

  # The configuration for addons supported by GKE
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Configuration options for the NetworkPolicy feature
  network_policy {
    provider = "CALICO"
    enabled = true
  }

  # Configuration for the PodSecurityPolicy feature
  pod_security_policy_config {
    enabled = false
  }

  # Configuration options for the Release channel feature, which provide more control over automatic upgrades of your GKE clusters.
  release_channel {
    channel = "STABLE"
  }

  # Workload Identity allows Kubernetes service accounts to act as a user-managed Google IAM Service Account.
  workload_identity_config {
    identity_namespace = "${var.project_id}.svc.id.goog"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.kubernetes-secrets.self_link
  }
  
  # Shielded Instance options
  #shielded_instance_config {
  #  enable_secure_boot = true
  #}

  # Disable basic authentication and cert-based authentication.
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  depends_on = [
    google_project_service.service,
    google_project_iam_member.service-account,
    google_compute_router_nat.nat
  ]
}

resource "google_container_node_pool" "gke-nodepools-default" {
  project = var.project_id
  name = "gke-nodepools-default"
  location = var.gke_devops_cluster_location
  cluster = google_container_cluster.gke-devops-cluster.name

  initial_node_count = 1

  node_config {
    machine_type = var.node_pools_machine_type
    
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]

    tags = [
      "gke-devops-nodes"]
  }
}

resource "google_container_node_pool" "gke-nodepools-devops" {
  project = var.project_id
  name = "gke-nodepools-devops"
  location = var.gke_devops_cluster_location
  cluster = google_container_cluster.gke-devops-cluster.name

  autoscaling {
    max_node_count = 3
    min_node_count = 0
  }

  node_config {
    machine_type = var.node_pools_machine_type
    preemptible  = true

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]

    labels = {
      "nodepool" = "devops"
    }

    taint {
        key = "devops-reserved-pool"
        value = "true"
        effect = "NO_SCHEDULE"
    }

    tags = [
      "gke-devops-nodes"]
  }
}


resource "google_container_node_pool" "gke-nodepools-vault" {
  project = var.project_id
  name = "gke-nodepools-vault"
  location = var.gke_devops_cluster_location
  cluster = google_container_cluster.gke-devops-cluster.name

  initial_node_count = 1 
  
  autoscaling {
    max_node_count = 3
    min_node_count = 1
  }

  node_config {
    machine_type = var.node_pools_machine_type
    service_account = google_service_account.vault-server.email

    metadata = {
      disable-legacy-endpoints = "true"
      google-compute-enable-virtio-rng = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      nodepool = "vault"
      service = "vault"
    }

    # Protect node metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }

    taint {
        key = "vault-reserved-pool"
        value = "true"
        effect = "NO_SCHEDULE"
    }
    
    tags = [
      "gke-devops-nodes", "vault"]
  }
}

# Provision IP
resource "google_compute_address" "vault" {
  name    = "vault-lb"
  region  = var.region
  project = var.project_id

  depends_on = [google_project_service.service]
}

output "address" {
  value = google_compute_address.vault.address
}

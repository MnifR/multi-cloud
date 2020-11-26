variable "gke_devops_cluster_location" {
  type = string
  default = "europe-west1"
}

variable "region" {
  type = string
}

variable "node_pools_machine_type" {
  type = string
  default = "e2-standard-2"
}

variable "master_ipv4_cidr_block" {
  type = string
}

variable "subnet_ip_range_primary" {
  type    = string
  default = "10.10.10.0/24"
}

variable "subnet_secondary_ip_range_services" {
  type    = string
  default = "10.10.11.0/24"
}

variable "subnet_secondary_ip_range_pods" {
  type    = string
  default = "10.1.0.0/20"
}

variable "public_dns_name" {
  type    = string
}

// deployment project id
variable "project_id" {
  type = string
}

variable "gitlab_public_ip_ranges" {
  type = string
  description = "GITLAB PUBLIC IP RANGES"
}

variable "vault_service_account_iam_roles" {
  type = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/storage.objectAdmin"
  ]
  description = "List of IAM roles to assign to the service account of vault."
}

variable "service_account_custom_iam_roles" {
  type        = list(string)
  default     = []
  description = "List of arbitrary additional IAM roles to attach to the service account on the Vault nodes."
}

variable "project_services" {
  type = list(string)
  default = [
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
  description = "List of services to enable on the project."
}

# This is an option used by the kubernetes provider, but is part of the Vault
# security posture.
variable "authorized_source_ranges" {
  type        = string
  description = "Addresses or CIDR blocks which are allowed to connect to the Vault IP address. The default behavior is to allow anyone (0.0.0.0/0) access. You should restrict access to external IPs that need to access the Vault cluster."
}

#
# KMS options
# ------------------------------

variable "kms_key_ring_prefix" {
  type        = string
  default     = "vault"
  description = "String value to prefix the generated key ring with."
}

variable "kms_key_ring" {
  type        = string
  default     = ""
  description = "String value to use for the name of the KMS key ring. This exists for backwards-compatability for users of the existing configurations. Please use kms_key_ring_prefix instead."
}

variable "kms_crypto_key" {
  type        = string
  default     = "vault-init"
  description = "String value to use for the name of the KMS crypto key."
}

variable "num_vault_pods" {
  type        = number
  default     = 3
  description = "Number of Vault pods to run. Anti-affinity rules spread pods across available nodes. Please use an odd number for better availability."
}

#
# Kubernetes options
# ------------------------------
variable "kubernetes_secrets_crypto_key" {
  type        = string
  default     = "kubernetes-secrets"
  description = "Name of the KMS key to use for encrypting the Kubernetes database."
}

variable "vault_container" {
  type        = string
  default     = "vault:1.2.1"
  description = "Name of the Vault container image to deploy. This can be specified like \"container:version\" or as a full container URL."
}

variable "vault_init_container" {
  type        = string
  default     = "sethvargo/vault-init:1.0.0"
  description = "Name of the Vault init container image to deploy. This can be specified like \"container:version\" or as a full container URL."
}

variable "vault_recovery_shares" {
  type        = string
  default     = "1"
  description = "Number of recovery keys to generate."
}

variable "vault_recovery_threshold" {
  type        = string
  default     = "1"
  description = "Number of recovery keys required for quorum. This must be less than or equal to \"vault_recovery_keys\"."
}

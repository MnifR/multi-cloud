resource "scaleway_k8s_cluster_beta" "k8s-cluster-demo" {
  name = "kapsule-cluster-${var.env}-demo"
  description = "K8S Demo ${var.env} Cluster"
  version = "1.19.4"
  cni = "calico"
  enable_dashboard = true
  ingress = "nginx"
  tags = [var.env, "demo"]

  autoscaler_config {
    disable_scale_down = false
    scale_down_delay_after_add = "5m"
    estimator = "binpacking"
    expander = "random"
    ignore_daemonsets_utilization = true
    balance_similar_node_groups = true
    expendable_pods_priority_cutoff = -5
  }
}

resource "scaleway_k8s_pool_beta" "k8s-pool-demo" {
  cluster_id = scaleway_k8s_cluster_beta.k8s-cluster-demo.id
  name = "kapsule-pool-${var.env}-demo"
  node_type = "DEV1-M"
  size = 3
  autoscaling = true
  autohealing = true
  min_size = 1
  max_size = 5
}

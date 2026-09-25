output "kubeconfig_path" {
  value       = abspath("~/.kube/config")
  description = "Path to configuration file kubernetes"
}

output "k3s_container_ip" {
  value       = docker_container.k3s.network_data[0].ip_address
  description = "IP-address container k3s in docker network dev-net"
}


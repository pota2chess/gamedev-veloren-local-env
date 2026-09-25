terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    sts = "http://localhost:4566"
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    ec2 = "http://localhost:4566"
  }
}

provider "docker" {}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

# Create custom docker network
resource "docker_network" "game-net" {
  name = "game-net"
}

# k3s
resource "docker_image" "k3s" {
  name         = "rancher/k3s:v1.36.4-rc1-k3s1"
  keep_locally = true
}

resource "docker_container" "k3s" {
  image      = docker_image.k3s.image_id
  name       = "k3s"
  command    = ["server", "--tls-san=k3s", "--disable=servicelb"]
  privileged = true
  networks_advanced {
    name = docker_network.game-net.name
  }
  ports {
    internal = 6443
    external = 6443
  }
  ports {
    internal = 8080
    external = 8080
  }

  provisioner "local-exec" {
    command = <<EOT
      until docker exec k3s test -f etc/rancher/k3s/k3s.yaml; do
        echo "Waiting create k3s.yaml"
        sleep 1
      done
      docker cp k3s:etc/rancher/k3s/k3s.yaml ~/.kube/config
    EOT
  }
}

# Localstack
resource "docker_image" "localstack" {
  name         = "localstack/localstack:latest"
  keep_locally = true
}

resource "docker_container" "localstack" {
  image = docker_image.localstack.image_id
  name  = "localstack"
  networks_advanced {
    name = docker_network.game-net.name
  }
  ports {
    internal = 4566
    external = 4566
  }
  env = [
    "LOCALSTACK_AUTH_TOKEN=${var.localstack_auth_token}",
    "DEBUG=${var.debug}",
    "PERSISTENCE=1" # Using for saving data between reboots
  ]
  volumes {
    container_path = "/var/lib/localstack"
    host_path      = "/mount/localstack/volume"
  }
  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
  }
  dynamic "ports" {
    for_each = range(4510, 4560)
    content {
      internal = ports.value
      external = ports.value
    }
  }
}

# Helm release for MetalLB
resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
}

# Helm release for veloren-server
resource "helm_release" "veloren-server-cli" {
  name             = "veloren-server-cli"
  repository       = null
  chart            = "${path.module}/../../kubernetes/veloren-server-cli"
  namespace        = "veloren-server-cli"
  create_namespace = true

  depends_on = [
    docker_container.k3s,
    helm_release.metallb
  ]
}

# Helm release for netdata
/*resource "helm_release" "netdata" {
  name             = "netdata"
  repository       = "https://netdata.github.io/helmchart"
  chart            = "netdata"
  namespace        = "netdata"
  create_namespace = true

  version = "3.7.173"
  wait    = true
}*/

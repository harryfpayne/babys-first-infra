terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "do_token" {
  default = "dop_v1_8abb0851ce958352732a6ca506c0c73d5b234a72d3cbabb53996ed58235576a2"
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_kubernetes_cluster" "cluster" {
  name   = "harry"
  region = "lon1"
  version = "1.29.1-do.0"

  node_pool {
    name       = "worker-pool"
    size       = "s-1vcpu-2gb"
    node_count = 1
  }
}

resource "digitalocean_container_registry" "container_registry" {
  name                   = "harry"
  subscription_tier_slug = "basic"
}

resource "digitalocean_container_registry_docker_credentials" "container_registry_credentials" {
  registry_name = digitalocean_container_registry.container_registry.name
}

provider "kubernetes" {
  host = digitalocean_kubernetes_cluster.cluster.endpoint
  token   = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
  )
}

resource "kubernetes_secret" "docker_credentials" {
  metadata {
    name = "docker-credentials"
  }

  data = {
    ".dockerconfigjson" = digitalocean_container_registry_docker_credentials.container_registry_credentials.docker_credentials
  }

  type = "kubernetes.io/dockerconfigjson"
}

provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.cluster.endpoint
    token                  = digitalocean_kubernetes_cluster.cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
      digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
    )
  }
}


resource "helm_release" "frontend" {
  name  = "frontend"
  chart = "${path.module}/../services/frontend/frontend"

  set {
    name  = "image.repository"
    value = "${digitalocean_container_registry.container_registry.endpoint}/frontend"
  }
  set {
    name  = "image.tag"
    value = "latest"
  }

  set {
    name = "imagePullSecretsName"
    value = kubernetes_secret.docker_credentials.metadata[0].name
  }

  set {
    name  = "service.port"
    value = "3000"
  }
  set {
    name  = "service.targetPort"
    value = "3000"
  }

  set {
      name  = "appName"
      value = "frontend"
  }
}

resource "kubernetes_deployment" "backend" {
  metadata {
    name = "backend"
    labels = {
      app = "backend"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app = "backend"
        }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_credentials.metadata[0].name
        }

        container {
          image = "${digitalocean_container_registry.container_registry.endpoint}/backend"
          name  = "example"

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "backend" {
  metadata {
    name = "backend"
  }
  spec {
    selector = {
      app = kubernetes_deployment.backend.metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}



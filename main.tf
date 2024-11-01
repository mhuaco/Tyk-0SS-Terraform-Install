terraform {
  // Specifies the required providers and versions for Helm and Kubernetes.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.22.0"
    }
  }
}

provider "kubernetes" {
  // Configures the Kubernetes provider to use a specific kubeconfig file and context.
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"  // Replace with your actual context name
}

provider "helm" {
  // Configures the Helm provider to use the same kubeconfig and context as Kubernetes.
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"  // Replace with your actual context name
  }
}

resource "random_password" "redis_password" {
  // Generates a random password for Redis without special characters, 16 characters long.
  length  = 16
  special = false
}



resource "kubernetes_namespace" "tyk" {
  // Creates the 'tyk' namespace if it does not already exist.
  metadata {
    name = "tyk"
  }
}



resource "helm_release" "redis" {
  // Deploys Redis using Helm from the Bitnami repository and specified chart version.
  name             = "tyk-redis-data"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "redis"
  version          = "19.0.2"
  namespace        = "tyk"
  create_namespace = false  // Reuses the existing 'tyk' namespace

  // Sets the password for Redis.
  set {
    name  = "auth.password"
    value = random_password.redis_password.result
  }
}




resource "helm_release" "tyk" {
  // Deploys the Tyk stack using Helm from the Tyk Helm chart repository.
  name       = "tyk-oss"
  repository = "https://helm.tyk.io/public/helm/charts"
  chart      = "tyk-oss"
  namespace  = "tyk"
  create_namespace = false

  // Loads custom configuration from a values file.
  values = [
    file("values.yaml")
  ]

  // Overrides specific values for Redis and MongoDB credentials in the Tyk stack.
  set {
    name  = "global.redis.pass"
    value = random_password.redis_password.result
  }


  // Specifies dependencies to ensure MongoDB and Redis are deployed before Tyk.
  depends_on = [
    helm_release.redis,
    
  ]
}



resource "kubernetes_service" "gateway_nodeport" {
  // Defines a NodePort service for the Tyk gateway, making it accessible externally.
  metadata {
    labels = {
      app = "gateway-svc-tyk-oss-tyk-gateway"
    }
    name      = "gateway-svc-tyk-oss-tyk-gateway-nodeport"
    namespace = "tyk"
  }

  spec {
    type = "NodePort"  // Service type for external access

    selector = {
      app = "gateway-tyk-oss-tyk-gateway"  // Label selector for Tyk gateway pods
    }

    port {
      port        = 8080     // External service port
      target_port = 8080     // Target port on the Tyk gateway pod
    }
  }

  // Ensures Tyk is deployed before creating the NodePort service.
  depends_on = [
    helm_release.tyk,
  ]
}




output "gateway_nodeport_url" {
  // Outputs the URL for accessing the Tyk gateway service.
  value       = "http://localhost:${kubernetes_service.gateway_nodeport.spec.0.port.0.node_port}/hello"
  description = "The accessible URL for the Tyk gateway service."
}

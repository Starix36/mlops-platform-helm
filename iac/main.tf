provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "ml_api_prod" {
  name       = "ml-api-production"
  repository = "oci://ghcr.io/yourusername/charts"
  chart      = "generic-ml-api"
  version    = "0.1.0"
  namespace  = "production"

  # Applying the specific environment values file
  values = [
    file("../env-values/prod-values.yaml")
  ]

  # Example of passing a sensitive variable via Terraform instead of Git
  set_sensitive {
    name  = "secrets.API_KEY"
    value = var.prod_api_key
  }
}

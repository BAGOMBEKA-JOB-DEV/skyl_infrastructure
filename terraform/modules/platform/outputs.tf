output "gateway_namespace" {
  description = "Namespace the gateway runs in."
  value       = var.gateway_namespace
}

output "gateway_release_name" {
  description = "Helm release name."
  value       = helm_release.skyl_gateway.name
}

output "gateway_image_digest" {
  description = "Image digest actually deployed. Record this with any incident."
  value       = var.gateway_image_digest
}

output "secret_store_name" {
  description = "ClusterSecretStore the gateway reads credentials through."
  value       = var.secret_store_name
}

output "endpoints" {
  description = "URLs the gateway serves, if an Ingress was configured."
  value       = [for h in var.gateway_hosts : "https://${h}"]
}

output "smoke_test" {
  description = "Commands to verify the deployment. See docs/runbook.md."
  value = <<-EOT
    kubectl -n ${var.gateway_namespace} rollout status deploy/skyl-gateway-skyl-gateway
    kubectl -n ${var.gateway_namespace} get externalsecret

    # Expect 200 with the token, 401 without.
    ${length(var.gateway_hosts) > 0 ?
  "curl -sSo /dev/null -w '%%{http_code}\\n' -H \"Authorization: Bearer $SKYL_AUTH_TOKEN\" https://${var.gateway_hosts[0]}/v1/providers"
: "kubectl -n ${var.gateway_namespace} port-forward svc/skyl-gateway-skyl-gateway 8080:80"}
  EOT
}

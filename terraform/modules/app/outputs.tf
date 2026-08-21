output "ui_ingress_hostname" {
  description = "ALB hostname for the retail app UI (once the ALB controller has reconciled the ingress)"
  value       = try(kubernetes_ingress_v1.ui.status[0].load_balancer[0].ingress[0].hostname, null)
}

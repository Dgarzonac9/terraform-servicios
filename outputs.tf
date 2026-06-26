output "ip_publica_balanceador" {
  description = "IP pública única de entrada"
  value       = google_compute_global_forwarding_rule.forwarding_rule.ip_address
}

output "escenario_activo" {
  value = "Principal: ${var.primary_weight}% | Contingencia: ${var.contingency_weight}%"
}
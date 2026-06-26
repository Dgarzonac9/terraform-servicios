variable "project_id" {
  description = "ID del proyecto en GCP"
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "primary_weight" {
  description = "Peso de tráfico al Servicio Principal (0-100)"
  type        = number
  default     = 100
}

variable "contingency_weight" {
  description = "Peso de tráfico al Servicio de Contingencia (0-100)"
  type        = number
  default     = 0
}
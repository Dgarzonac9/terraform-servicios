\# AGENTS.md - Guía para LLM



Este documento explica cómo leer y entender este proyecto de Terraform para GCP.



\## ¿Qué hace este proyecto?



Despliega una infraestructura en Google Cloud Platform que simula un sistema de \*\*control de tráfico web\*\* entre dos servicios:



\- \*\*Servicio Principal\*\*: página de producción (fondo verde)

\- \*\*Servicio de Contingencia\*\*: página de mantenimiento con Error 503 (fondo rojo)



Ambos servicios están detrás de un único balanceador de carga HTTP con una sola IP pública. El porcentaje de tráfico que va a cada servicio se controla con dos variables numéricas.



\## Archivos del proyecto



| Archivo | Propósito |

|---|---|

| `main.tf` | Define todos los recursos de GCP (VMs, red, balanceador, NAT) |

| `variables.tf` | Declara las variables que acepta el proyecto |

| `terraform.tfvars` | Valores concretos de las variables (aquí se cambian los escenarios) |

| `outputs.tf` | Muestra la IP pública y el escenario activo tras el despliegue |



\## Cómo leer main.tf



El archivo sigue este orden lógico de recursos:



1\. \*\*Provider y configuración\*\* — conecta Terraform con GCP usando el project\_id

2\. \*\*Red (VPC + subred)\*\* — red privada aislada, sin IPs públicas en las VMs

3\. \*\*Firewall\*\* — permite tráfico HTTP (puerto 80) desde internet y desde el health checker de GCP (rangos 130.211.0.0/22 y 35.191.0.0/16)

4\. \*\*Cloud NAT + Router\*\* — permite que las VMs sin IP pública descarguen paquetes de internet (necesario para instalar nginx)

5\. \*\*VMs (google\_compute\_instance)\*\* — dos instancias e2-micro con Debian 12; el startup script instala nginx y escribe el HTML de cada servicio

6\. \*\*Instance Groups\*\* — agrupan cada VM para conectarla al balanceador

7\. \*\*Health Check\*\* — verifica cada 10 segundos que nginx responda en el puerto 80

8\. \*\*Backend Services\*\* — uno por cada servicio, con esquema EXTERNAL\_MANAGED (requerido para tráfico ponderado)

9\. \*\*URL Map\*\* — aquí ocurre el split de tráfico con `weighted\_backend\_services`; los pesos vienen de las variables `primary\_weight` y `contingency\_weight`

10\. \*\*HTTP Proxy + Forwarding Rule\*\* — exponen el balanceador en una IP pública en el puerto 80



\## Variable clave: los pesos de tráfico



El split de tráfico se controla en `terraform.tfvars` con dos variables:



```hcl

primary\_weight     = 100   # % de tráfico al servicio principal

contingency\_weight = 0     # % de tráfico al servicio de contingencia

```



GCP interpreta estos valores como pesos relativos, no porcentajes exactos. Si ambos son 50, el tráfico se distribuye equitativamente. Si uno es 0, ese backend no recibe tráfico.



\## Los 3 escenarios



\### Escenario 1 — Producción activa

```hcl

primary\_weight     = 100

contingency\_weight = 0

```

Todo el tráfico va al servicio principal. El usuario ve "Bienvenido al Servicio Principal - Version Produccion".



\### Escenario 2 — Mantenimiento total

```hcl

primary\_weight     = 0

contingency\_weight = 100

```

Todo el tráfico va al servicio de contingencia. El usuario ve "Error 503 - Sitio en Mantenimiento Programado".



\### Escenario 3 — Balance equitativo

```hcl

primary\_weight     = 50

contingency\_weight = 50

```

El tráfico se distribuye entre ambos servicios. Por session affinity del balanceador, el mismo cliente tiende a ir siempre al mismo backend. Para observar ambas respuestas se recomienda hacer múltiples peticiones desde diferentes clientes o usar herramientas como curl en un loop.



\## Cómo desplegar



```bash

\# 1. Autenticarse

gcloud auth login

gcloud auth application-default login --scopes="https://www.googleapis.com/auth/cloud-platform"



\# 2. Editar terraform.tfvars con el project\_id real



\# 3. Desplegar

terraform init

terraform apply



\# 4. Cambiar escenario: editar terraform.tfvars y volver a aplicar

terraform apply



\# 5. Destruir al terminar

terraform destroy

```



\## Decisiones de diseño importantes



\- \*\*Sin IP pública en las VMs\*\*: las VMs solo tienen IP interna. El acceso a internet para instalar nginx se hace via Cloud NAT. Esto es una buena práctica de seguridad.

\- \*\*EXTERNAL\_MANAGED\*\*: el esquema de balanceo debe ser EXTERNAL\_MANAGED (no EXTERNAL) para poder usar weighted\_backend\_services en el URL map. El esquema EXTERNAL clásico no soporta esta funcionalidad.

\- \*\*Startup script en una línea\*\*: el script de arranque está escrito en una sola línea con `\\n` para evitar problemas de codificación CRLF en Windows, que rompían el script cuando se usaban heredocs multilínea.

\- \*\*Health check\*\*: el balanceador solo envía tráfico a backends HEALTHY. Si nginx no está corriendo, la VM queda UNHEALTHY y no recibe peticiones.



\## Posibles problemas y soluciones



| Problema | Causa | Solución |

|---|---|---|

| VM UNHEALTHY después del deploy | Startup script no terminó aún | Esperar 3-4 min y hacer `gcloud compute instances reset` si persiste |

| Startup script falla con "network unreachable" | No hay Cloud NAT configurado | Agregar `google\_compute\_router` y `google\_compute\_router\_nat` |

| Error 400 en URL map | Usando EXTERNAL en vez de EXTERNAL\_MANAGED | Cambiar `load\_balancing\_scheme` en backend services y forwarding rule |

| Página no cambia al cambiar escenario | Cache del navegador o propagación del LB | Usar Ctrl+Shift+R o esperar 1-2 minutos |


## 📖 SDWAN OPEN SOURCE

Este repositorio proporciona una solución automatizada de Infraestructura como Código (IaC) para desplegar una red de área extensa definida por software (SD-WAN) utilizando una topología **Hub-and-Spoke** (estrella). Construido estrictamente sobre tecnologías de código abierto, el proyecto utiliza **Ansible** para orquestar y gestionar de forma centralizada una flota de enrutadores **VyOS**.

### Arquitectura y Objetivos Core

El objetivo principal del proyecto es establecer una red superpuesta (overlay) segura, dinámica y tolerante a fallos a través de múltiples ubicaciones geográficas (una sede central o _Hub_ y varias sucursales o _Spokes_). A nivel técnico, el proyecto se sostiene sobre tres pilares que el README original no terminaba de interconectar:

1. **Automatización Determinista (Ansible):** Todo el aprovisionamiento de los nodos se ejecuta de forma remota desde una máquina controladora basada en Debian. Esto elimina el riesgo de "configuration drift" (desviación de configuración) mediante playbooks idempotentes que configuran desde claves SSH y zonas horarias, hasta topologías de red complejas.
    
2. **Overlay Cifrado de Alta Disponibilidad (WireGuard):** Establece túneles de encriptación de alta velocidad entre el Hub (`hq`) y los Spokes (`sede1` a `sede4`). La topología implementa redundancia creando dos interfaces separadas (`wg0` para el túnel principal y `wg1` para el _failover_ o respaldo).
    
3. **Enrutamiento Dinámico (BGP):** El componente más crítico (y omitido en la documentación original). Sobre los túneles estáticos de WireGuard, el proyecto inyecta el protocolo BGP (`BgpConfiguration.yml`) para anunciar y aprender dinámicamente las rutas de las redes LAN locales. Esto permite que la red sea escalable y capaz de redirigir el tráfico automáticamente si un enlace falla.

En resumen, el proyecto emula el comportamiento de soluciones SD-WAN empresariales propietarias (como Cisco o Fortinet), utilizando exclusivamente herramientas Open Source para crear una red corporativa resiliente y automatizada.

---

## 🛠 Requisitos Previos

Para asegurar un despliegue exitoso, el entorno debe cumplir con las siguientes especificaciones técnicas. Se ha detectado que la configuración depende críticamente de la comunicación vía `network_cli`.

### 1. Control Node (Máquina Controladora)

Debe ser un sistema basado en Linux (preferiblemente Debian/Ubuntu) con las siguientes dependencias instaladas:

- **Ansible (>= 2.9):** Orquestador principal.
    
- **Python 3 & Pip3:** Entorno de ejecución.
    
- **Módulos de red:** Es indispensable `ansible-pylibssh` para gestionar conexiones seguras con VyOS sin depender del binario de SSH del sistema.
    
- **WireGuard Tools:** Necesario localmente para la generación de pares de claves (`wg genkey`).

```bash
# Instalación de dependencias en Debian/Ubuntu
sudo apt update && sudo apt install -y ansible python3 python3-pip wireguard-tools
pip3 install ansible-pylibssh --break-system-packages
```

### 2. Managed Nodes (Instancias VyOS)

Cada nodo (Hub y Spokes) debe tener un estado base mínimo antes de ejecutar los playbooks:

- **Acceso SSH:** El servicio debe estar activo en el puerto 22.
    
- **Conectividad WAN:** Cada router debe tener salida a internet y una IP alcanzable por la controladora.
    
- **Credenciales:** Usuario `vyos` configurado con permisos de administración.

---

## 📂 Estructura del Proyecto

He analizado la disposición de los archivos para organizar la lógica de configuración. Esta es la jerarquía funcional del repositorio:

- `hosts`: Inventario centralizado donde se definen los grupos `headquarters` (Hub) y `headquartersbck` (Backup/Spokes).
    
- `ansible.cfg`: Configuración global para optimizar la conexión (desactiva el chequeo de claves de host para entornos dinámicos).
    
- `group_vars/` & `host_vars/`: **Crítico.** Aquí reside la inteligencia del proyecto. Se deben definir variables como `lan_ip` y `wg_ip` de forma individual para evitar colisiones de rutas en el Hub.
    
- `files/`: Directorio destinado a almacenar las claves públicas (`.pub`) y privadas (`.key`) de WireGuard generadas dinámicamente.
    
- `gekey.sh`: Script de automatización para la creación masiva de claves criptográficas.
    
- **Playbooks Principales:**
    
    - `GlobalConfigurationHub.yml`: Configuración base del sistema (hostname, SSH keys, timezone).
        
    - `WireguardConfiguration.yml` (y `v2`): Despliegue de la capa de transporte cifrada.
        
    - `BgpConfiguration.yml`: Configuración de la capa de enrutamiento dinámico sobre los túneles.

> [!WARNING]
> NO SE RECOMIENDA HACER USO DEL ARCHIVO all-in-one.yml.

---

## 🚀 Guía de Despliegue

El despliegue se realiza en capas, desde la base del sistema hasta la inteligencia de enrutamiento.

### Paso 1: Preparación del Inventario y Seguridad

Edita el archivo `hosts`. **Advertencia técnica:** Evita el uso de `ansible_ssh_pass`. El primer playbook del proyecto ya está diseñado para inyectar tu llave pública (`sshkey.pub`), por lo que solo necesitas acceso por contraseña para la primera ejecución.

Si vas a hacer uso de clave SSH debes insertar la clave pública en el fichero `files/sshkey.pub`, como en el ejemplo:
```txt
AAAAB3NzaC1yc2EAAAADAQABAAABAQCoDgfhQJuJRFWJijHn7ZinZ3NWp4hWVrt7HFcvn0kgtP/5PeCtMt
```
SOLO LA CLAVE.

### Paso 2: Generación Criptográfica

No puedes configurar WireGuard sin las llaves. El script `gekey.sh` automatiza esto. Asegúrate de que el array `names` en el script coincida exactamente con los nombres de host en tu inventario.

```bash
# Otorgar permisos y ejecutar
chmod +x gekey.sh
./gekey.sh
```

Esto poblará la carpeta `files/` con los pares de llaves necesarios para el Hub y los Spokes.

### Paso 3: Aprovisionamiento Base e Interfaz de Red

Ejecuta el primer playbook para preparar los nodos VyOS.

```bash
ansible-playbook -i hosts GlobalConfigurationHub.yml
```

**Lo que ocurre internamente:** Se establece el hostname, la zona horaria, etc...
Los cambios realizados se guardarán en el disco asegurando la persistencia de la configuación.

### Paso 4: Despliegue de la VPN

Una vez que los nodos tienen conectividad base, procedemos a levantar los túneles cifrados. El proyecto utiliza dos archivos distintos para permitir una topología de doble túnel (redundancia).

**Importante:** Verifica que las llaves generadas en el paso anterior existan en la carpeta `files/` antes de continuar.

```bash
# Despliegue del túnel principal (wg0)
ansible-playbook -i hosts WireguardConfiguration.yml

# Despliegue del túnel de respaldo/failover (wg1)
ansible-playbook -i hosts WireguardConfiguration2.yml
```

**Validación técnica:** En este punto, si entras en cualquier router VyOS y ejecutas `show interfaces wireguard`, deberías ver las interfaces `wg0` y `wg1` con estado **u/u** (up/up) y tráfico fluyendo si los Spokes ya intentaron el _handshake_ con el Hub.

### Paso 5: Activación de SD-WAN con BGP (Capa de Control)

Con los túneles activos, inyectamos el protocolo de enrutamiento dinámico. Esto es lo que permite que una red LAN detrás de la `Sede 1` sea visible para la `Sede 4` sin rutas estáticas manuales.

```bash
ansible-playbook -i hosts BgpConfiguration.yml
```

**Lógica del despliegue:**

1. **Hub (hq):** Se configura como _Route Reflector_ (RR). Esto evita que tengas que configurar una malla completa (_Full Mesh_) de vecinos BGP; todos los Spokes hablan con el Hub y este redistribuye las rutas.
    
2. **Spokes:** Inician una sesión BGP hacia la IP del túnel del Hub (ej. `10.10.10.1`).

---

## Verification & Troubleshooting / Verificación y Diagnóstico

Para confirmar que la SD-WAN está operativa, utiliza los siguientes comandos directamente en los nodos VyOS:

### 1. Estado de los Túneles

```bash
show interfaces wireguard
# Debe mostrar el "Latest handshake" hace menos de 2-3 minutos.
```

### 2. Vecindad BGP

```bash
show ip bgp summary
# El estado (State/PfxRcd) debe ser un número (cantidad de rutas recibidas). 
# Si dice "Active" o "Idle", la conexión está fallando.
```

### 3. Tabla de Rutas Global

```bash
show ip route bgp
# Aquí verás las subredes de las otras sedes aprendidas a través de las interfaces wgX.
```

---
## 🛡️ WireGuard

Para que BGP pueda enrutar tráfico dinámicamente y gestionar la redundancia entre distintas sedes, primero construimos una red subyacente segura. Este proyecto descarta soluciones legadas (como IPsec/IKEv2) y adopta **WireGuard** como la piedra angular de su capa de transporte.

### ¿Por qué WireGuard para esta SD-WAN?

1. **Rendimiento Criptográfico (Kernel-Space):** WireGuard opera directamente en el espacio del kernel de Linux (base de VyOS), utilizando primitivas criptográficas modernas (ChaCha20, Poly1305). Esto reduce drásticamente el uso de CPU frente a IPsec y maximiza el ancho de banda.
    
2. **Naturaleza "Stateless" (Sin Estado):** No hay pesados procesos de negociación de fases. Si un enlace físico cae y se levanta, WireGuard simplemente reanuda la transmisión de paquetes cifrados. Esto es vital para que BGP pueda conmutar el tráfico rápidamente entre el túnel principal (`wg0`) y el de respaldo (`wg1`).
    
3. **Agilidad Estructural:** WireGuard crea interfaces de red virtuales (`wgX`) a las que se les asignan direcciones IP, proporcionando a BGP las "puertas de enlace" necesarias para establecer vecindad.

### La Configuración y el "Cryptokey Routing"

WireGuard basa su seguridad y flujo de tráfico en el concepto de _Cryptokey Routing_. Cada nodo tiene una clave pública y una privada. Cuando el router Hub quiere enviar un paquete hacia un Spoke, evalúa una tabla interna llamada `allowed-ips` vinculada a la clave pública de ese destino.

#### Parámetros Clave en la Arquitectura:

- **`endpoint` (En los Spokes):** Define la IP pública y el puerto (UDP/51820 y 51821) del Hub central para iniciar la conexión.
    
- **`persistent-keepalive 25`:** Crítico para sedes en NAT. Enviar un paquete vacío cada 25 segundos mantiene abierta la tabla de traducción del firewall del proveedor de internet, garantizando que el túnel bidireccional no se "congele".
    
- **`allowed-ips` (El Puente entre WireGuard y BGP):** En esta topología, la seguridad es restrictiva. En el router Hub, el parámetro `allowed-ips` de cada Spoke no solo incluye la IP del túnel (ej. `10.10.10.2/32`), sino que **debe declarar explícitamente los rangos de la red LAN interna** de esa sede (ej. `192.168.20.0/24`).

### 🧠 Interacción BGP y WireGuard (Flujo de Trabajo)

El diseño implementa una validación en dos capas:

1. **Capa BGP (Dinámica):** Se encarga de monitorear la salud de los enlaces. Si el túnel `wg0` cae, BGP retira la ruta hacia la LAN de la sede y activa la ruta a través de `wg1`.
    
2. **Capa WireGuard (Estricta):** Actúa como firewall criptográfico. Solo permite el paso de tráfico hacia las redes LAN que hayan sido provisionadas previamente por Ansible en los `allowed-ips`. Esto garantiza que, incluso si una sede maliciosa intenta anunciar una ruta BGP falsa, WireGuard descartará el tráfico en el Hub, manteniendo la red segmentada y segura.

---

## 🌐 Dynamic Routing: eBGP

A diferencia de una VPN tradicional, esta SD-WAN elimina la necesidad de rutas estáticas manuales mediante el uso de **eBGP (External Border Gateway Protocol)** para gestionar la alcanzabilidad dinámica de las redes LAN a través de los túneles WireGuard.

### Configuración de la Topología BGP

El diseño utiliza un modelo de tránsito eBGP centralizado para la distribución de prefijos:

- **El Hub (hq) como Enrutador de Tránsito:** Opera en su propio Sistema Autónomo (ej. AS 65000). Actúa como el punto central de intercambio de rutas. Recibe los anuncios de red (prefijos LAN) de cada sucursal, actualiza el atributo `AS-PATH` añadiendo su propio ASN, y reanuncia estas rutas al resto de los túneles conectados. Esto permite la comunicación fluida _spoke-to-spoke_ pasando por el Hub.
    
- **Los Spokes (Sedes Periféricas):** Operan en un Sistema Autónomo diferente al resto. Cada sede establece una adyacencia eBGP apuntando a la IP de la interfaz WireGuard del Hub (`10.10.10.1`). Cada router Spoke se encarga de inyectar su red local (definida en la variable `lan_ip`) en el proceso BGP.
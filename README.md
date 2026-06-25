# Proyecto: Automatización VPN IPSec/GRE/OSPF Full-Mesh con Ansible

**Redes Avanzadas I — INACAP**
**Integrantes:** Benjamin Riquelme Landero · David Pradenas Leiva

---

## Descripción

Este proyecto automatiza la configuración de una topología VPN full-mesh entre tres
routers Cisco IOSv usando Ansible. La solución implementa:

- **GRE**: túneles de capa 3 entre cada par de routers (3 túneles en total)
- **IPSec**: cifrado AES-256 sobre cada túnel GRE (IKEv1)
- **OSPF**: enrutamiento dinámico dentro de la VPN para descubrir las LANs de cada sitio

El contenedor Ansible corre **dentro de la topología GNS3**, conectado a la red de
gestión, y configura los tres routers vía SSH.

---

## Topología

```
          192.168.1.0/24              192.168.3.0/24
               |                           |
            R1 (10.0.0.1) ─────────── R3 (10.0.0.3)
               \                         /
                \                       /
                 R2 (10.0.0.2)
                     |
               192.168.2.0/24

[Ansible Container: 10.0.0.100]
```

### Túneles GRE (full-mesh)

| Túnel | Router A | IP A | Router B | IP B |
|-------|----------|------|----------|------|
| R1↔R2 | R1 Tunnel12 | 172.16.12.1/30 | R2 Tunnel21 | 172.16.12.2/30 |
| R1↔R3 | R1 Tunnel13 | 172.16.13.1/30 | R3 Tunnel31 | 172.16.13.2/30 |
| R2↔R3 | R2 Tunnel23 | 172.16.23.1/30 | R3 Tunnel32 | 172.16.23.2/30 |

---

## Requisitos previos

- GNS3 instalado con imagen **Cisco IOSv**
- Docker instalado en la laptop
- Los 3 routers y el contenedor conectados a la misma red en GNS3

---

## Estructura del proyecto

```
ansible-vpn-project/
├── Dockerfile                  # Contenedor Ansible para GNS3
├── ansible.cfg                 # Configuración global de Ansible
├── requirements.yml            # Colecciones Ansible necesarias
├── inventory/
│   ├── hosts.ini               # Lista de routers
│   ├── group_vars/
│   │   └── all.yml             # Variables globales (OSPF, IPSec, IKE)
│   └── host_vars/
│       ├── R1.yml              # IPs, túneles y peers de R1
│       ├── R2.yml
│       └── R3.yml
├── roles/
│   ├── base/                   # Hostname, SSH, interfaces físicas
│   ├── gre_tunnels/            # Configuración de túneles GRE
│   ├── ipsec/                  # Cifrado IPSec sobre GRE
│   └── ospf/                   # Enrutamiento OSPF
└── playbooks/
    ├── site.yml                # Playbook principal (despliega todo)
    └── rollback.yml            # Deshace la configuración VPN
```

---

## Configuración inicial de los routers (manual, una sola vez)

Antes de ejecutar Ansible, cada router necesita una configuración mínima para que
Ansible pueda conectarse por SSH:

```
! Ejecutar en CADA router en GNS3 (consola)
enable
configure terminal

! R1: usar ip 10.0.0.1 | R2: 10.0.0.2 | R3: 10.0.0.3
interface GigabitEthernet0/0
 ip address 10.0.0.X 255.255.255.0
 no shutdown
 exit

hostname RX
ip domain-name lab.local
username admin privilege 15 secret admin123
enable secret enable123
crypto key generate rsa modulus 2048
ip ssh version 2
line vty 0 4
 transport input ssh
 login local
 exit
end
write memory
```

---

## Uso

### 1. Construir el contenedor Ansible

```bash
# Desde la raíz del proyecto
docker build -t ansible-vpn .
```

### 2. Agregar el contenedor a GNS3

En GNS3: **Edit → Preferences → Docker containers → New**
- Image: `ansible-vpn`
- Conectar a la misma red que los routers

### 3. Ejecutar el playbook principal

```bash
# Dentro del contenedor Ansible (consola GNS3)
cd /ansible

# Instalar colecciones
ansible-galaxy collection install -r requirements.yml

# Verificar conectividad con los routers
ansible routers -m ping

# Despliegue completo
ansible-playbook playbooks/site.yml

# Solo una fase específica
ansible-playbook playbooks/site.yml --tags gre
ansible-playbook playbooks/site.yml --tags ipsec
ansible-playbook playbooks/site.yml --tags ospf

# Modo check (no aplica cambios, solo muestra qué haría)
ansible-playbook playbooks/site.yml --check --diff
```

### 4. Rollback

```bash
ansible-playbook playbooks/rollback.yml
```

---

## Verificación manual

Desde cualquier router, después del despliegue:

```
! Ver vecinos OSPF (debe mostrar 2 vecinos)
show ip ospf neighbor

! Ver rutas aprendidas por OSPF
show ip route ospf

! Ver SAs IPSec activas
show crypto ipsec sa summary

! Ping entre LANs a través de la VPN
ping 192.168.2.1 source GigabitEthernet0/1
ping 192.168.3.1 source GigabitEthernet0/1
```

---

## Seguridad

Las contraseñas en `group_vars/all.yml` y `host_vars/` son de laboratorio.
En producción, usar **ansible-vault**:

```bash
# Cifrar archivo de variables sensibles
ansible-vault encrypt inventory/group_vars/all.yml

# Ejecutar playbook con vault
ansible-playbook playbooks/site.yml --ask-vault-pass
```

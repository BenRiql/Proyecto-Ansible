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

## CI/CD con GitHub Actions

El proyecto incluye un pipeline automatizado en `.github/workflows/ci-cd.yml` con 4 etapas:

```
push/PR a main
      │
      ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐     ┌──────────────┐
│    lint     │────▶│     dry-run      │────▶│   deploy    │────▶│   notify     │
│ (GitHub-    │     │ (self-hosted,    │     │ (self-hosted│     │ (GitHub-     │
│  hosted)    │     │  contra GNS3)    │     │  solo main) │     │  hosted)     │
└─────────────┘     └──────────────────┘     └─────────────┘     └──────────────┘
yamllint             ansible-playbook          ansible-playbook     email con
ansible-lint         --check --diff            site.yml completo    resultado
syntax-check                                   + verificación       final
```

- **lint**: corre en un runner de GitHub (no necesita el laboratorio). Valida sintaxis YAML,
  buenas prácticas de Ansible y que los playbooks parseen correctamente.
- **dry-run**: corre en un runner **self-hosted** (dentro del contenedor Ansible en GNS3,
  con acceso a la red 10.0.0.0/24 de los routers). Simula los cambios con `--check --diff`
  sin aplicarlos.
- **deploy**: solo se ejecuta automáticamente en push a `main`, y solo si `lint` y `dry-run`
  pasaron. Aplica la configuración real y corre la verificación end-to-end (`--tags verify`).
- **notify**: envía un correo con el resultado del pipeline (éxito o falla), sin importar
  en qué etapa haya terminado.

### 1. Registrar el runner self-hosted

El runner corre dentro del contenedor Ansible de la topología GNS3, porque es el único punto
con acceso simultáneo a internet (necesario para hablar con GitHub) y a la red de los routers.
Para esto se le agregó una segunda interfaz de red al contenedor, conectada a un nodo NAT.

En GitHub: **Actions → Runners → New self-hosted runner** (Linux/x64), y dentro de la consola
del contenedor:

```bash
mkdir -p /opt/actions-runner && cd /opt/actions-runner
curl -o actions-runner-linux-x64-2.335.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-linux-x64-2.335.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.335.1.tar.gz
./bin/installdependencies.sh

export RUNNER_ALLOW_RUNASROOT=1
./config.sh --url https://github.com/BenRiql/Proyecto-Ansible --token <TOKEN_QUE_DA_GITHUB>

# Dejarlo corriendo en segundo plano, para que no se corte al cerrar la terminal
nohup ./run.sh > runner.log 2>&1 &
```

Nota: como el contenedor GNS3 puede perder el filesystem entre reinicios, si el runner
desaparece hay que repetir estos pasos con un token nuevo (se genera desde la misma pantalla
de GitHub).

### 2. Configurar los Secrets del repositorio

En **Settings → Secrets and variables → Actions → New repository secret**, crear:

| Secret | Descripción |
|---|---|
| `ANSIBLE_USER` | Usuario SSH de los routers |
| `ANSIBLE_PASSWORD` | Contraseña SSH |
| `ANSIBLE_BECOME_PASSWORD` | Contraseña de modo enable |
| `IPSEC_PSK` | Clave precompartida IPSec |
| `EMAIL_USERNAME` | Correo Gmail remitente |
| `EMAIL_PASSWORD` | [Contraseña de aplicación de Gmail](https://myaccount.google.com/apppasswords) (no la contraseña normal) |
| `EMAIL_TO` | Correo(s) donde llega la notificación |

### 3. Disparar el pipeline

Con GNS3 y el runner corriendo:

```bash
git add .
git commit -m "feat: cambio de ejemplo"
git push origin main
```

También se puede disparar manualmente desde la pestaña **Actions** del repo (`workflow_dispatch`).

## Seguridad

Las credenciales (`ansible_password`, `ansible_become_password`, `ipsec_preshared_key`) ya
**no están hardcodeadas** en el repositorio: se leen desde variables de entorno mediante
`lookup('env', ...)` en `inventory/hosts.ini` y `inventory/group_vars/all.yml`.

**Para ejecutar localmente** (fuera de CI/CD):

```bash
cp .env.example .env
# Edita .env con tus valores reales (este archivo NUNCA se sube a git)
export $(grep -v '^#' .env | xargs)
ansible routers -m ping
```

**En CI/CD**, estas mismas variables se inyectan automáticamente desde los **Secrets de
GitHub Actions** (ver sección de CI/CD más arriba) — nunca quedan expuestas en el código
ni en los logs del pipeline.

Como alternativa/complemento, también se puede usar **ansible-vault** para cifrar archivos
completos:

```bash
ansible-vault encrypt inventory/group_vars/all.yml
ansible-playbook playbooks/site.yml --ask-vault-pass
```

## Historial de troubleshooting (Fase 2)

Durante la implementación del pipeline CI/CD se resolvieron los siguientes problemas reales:

- Credenciales SSH/enable movidas de texto plano a variables de entorno y GitHub Secrets.
- Hallazgos de `ansible-lint` corregidos (FQCN en módulos, naming de handlers).
- Runner self-hosted registrado dentro del contenedor Ansible en GNS3, con una interfaz de red adicional conectada a un nodo NAT para dar acceso a internet sin perder la conectividad al laboratorio.
- Ajuste del playbook de verificación end-to-end para que el ping funcione correctamente también en modo `--check` (dry-run).

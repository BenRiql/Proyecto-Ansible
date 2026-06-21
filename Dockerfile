FROM python:3.11-slim

LABEL maintainer="Redes Avanzadas I - INACAP"
LABEL description="Contenedor Ansible para automatización de red Cisco IOSv"

# Dependencias del sistema
RUN apt-get update && apt-get install -y \
    openssh-client \
    sshpass \
    iputils-ping \
    iproute2 \
    net-tools \
    curl \
    git \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instalar Ansible y dependencias Python para Cisco IOS
RUN pip install --no-cache-dir \
    ansible==9.5.1 \
    ansible-lint==6.22.2 \
    yamllint==1.35.1 \
    paramiko==3.4.0 \
    netmiko==4.3.0 \
    ncclient==0.6.15
    netaddr==1.3.0
# Instalar colección oficial de Cisco IOS para Ansible
RUN ansible-galaxy collection install cisco.ios:==4.6.1

# Directorio de trabajo dentro del contenedor
WORKDIR /ansible

# Copiar proyecto al contenedor
COPY . /ansible/

# Configuración SSH para no verificar host keys (laboratorio)
RUN mkdir -p /root/.ssh && \
    echo "Host *\n\
    StrictHostKeyChecking no\n\
    UserKnownHostsFile /dev/null\n\
    ServerAliveInterval 30\n\
    ServerAliveCountMax 3" > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Exponer nada — este contenedor solo hace outbound SSH
CMD ["/bin/bash"]

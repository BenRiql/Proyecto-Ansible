#!/bin/bash
echo "╔══════════════════════════════════════════╗"
echo "║     Ansible VPN Automation Container     ║"
echo "║     Redes Avanzadas I — INACAP           ║"
echo "╚══════════════════════════════════════════╝"
echo "[*] Configurando interfaz eth0..."
ifconfig eth0 10.0.0.100 netmask 255.255.255.0 up
echo "[*] Verificando conectividad con los routers..."
for router in 10.0.0.1 10.0.0.2 10.0.0.3; do
    if ping -c 1 -W 2 $router > /dev/null 2>&1; then
        echo "    OK $router"
    else
        echo "    FALLA $router"
    fi
done
echo ""
echo "[*] Listo! Comandos disponibles:"
echo "    ansible routers -m ping"
echo "    ansible-playbook playbooks/site.yml"
echo ""
/bin/bash

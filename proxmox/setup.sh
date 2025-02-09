#!/bin/bash

# -------------------------------------------------------------------
# Configuration personnalisable
# -------------------------------------------------------------------

# Nom du bridge interne
BRIDGE_NAME="localbr1"

# Réseau interne
BRIDGE_IP="10.0.0.1/24"          # IP du bridge sur l'hôte
LXC_IP="10.0.0.100"              # IP du conteneur Nginx Proxy Manager
INTERNAL_NETWORK="10.0.0.0/24"   # Plage du réseau interne

# Ports à rediriger vers le LXC
PORTS_TO_FORWARD="80 443 81"

# -------------------------------------------------------------------
# Étape 1 : Création du bridge personnalisé (sans écraser la config existante)
# -------------------------------------------------------------------

# Fichier de configuration réseau
INTERFACES_FILE="/etc/network/interfaces"

# Ajoutez la configuration du bridge à la fin du fichier
if ! grep -q "auto $BRIDGE_NAME" "$INTERFACES_FILE"; then
    cat >> "$INTERFACES_FILE" <<EOF

# Bridge interne pour les LXC (ajouté automatiquement)
auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
    address $BRIDGE_IP
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF
fi

# Redémarrage du réseau
systemctl restart networking

# -------------------------------------------------------------------
# Étape 2 : Configuration du NAT et routage
# -------------------------------------------------------------------

# Activation du forwarding IPv4
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Règles iptables (NAT + Forwarding)
iptables -t nat -A POSTROUTING -s $INTERNAL_NETWORK -o vmbr0 -j MASQUERADE
iptables -A FORWARD -i $BRIDGE_NAME -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o $BRIDGE_NAME -m state --state RELATED,ESTABLISHED -j ACCEPT

# Redirection des ports (uniquement sur l'interface publique vmbr0)
for port in $PORTS_TO_FORWARD; do
    iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport $port -j DNAT --to-destination $LXC_IP:$port
done

# Persistance des règles
if ! dpkg -l | grep -q iptables-persistent; then
    apt install -y iptables-persistent
fi
iptables-save > /etc/iptables/rules.v4

# -------------------------------------------------------------------
# Étape 3 : Instructions pour le LXC
# -------------------------------------------------------------------

echo ""
echo "✅ Configuration réussie !"
echo ""
echo "➜ Pour utiliser le bridge '$BRIDGE_NAME' dans un LXC :"
echo "Dans l'interface Proxmox, ajoutez une interface réseau au conteneur avec :"
echo "   - Bridge: $BRIDGE_NAME"
echo "   - IP: $LXC_IP/24"
echo "   - Gateway: ${BRIDGE_IP%/*}"  # Retire le masque (ex: 10.42.42.1)

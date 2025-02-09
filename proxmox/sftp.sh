#!/bin/bash

# =============================================
# CONFIGURATION SFTP POUR LXC ALPINE (VERSION MODERNISÉE)
# =============================================

set -e  # Arrêt en cas d'erreur

# Configuration
SFTP_GROUP="sftp_users"
LXC_NETWORK="10.0.0"

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31m[ERREUR]\033[0m Ce script doit être exécuté en root !" >&2
    exit 1
fi

# Fonction d'exécution dans LXC
lxc_exec() {
    pct exec "$LXC_ID" -- sh -c "$1" || {
        echo -e "\033[31m[ERREUR CRITIQUE]\033[0m Échec de la commande LXC : $1" >&2
        exit 1
    }
}

# Vérification et démarrage du LXC
verify_lxc() {
    while true; do
        read -rp "Entrez le numéro du LXC : " LXC_ID
        pct status "$LXC_ID" &>/dev/null && break
        echo -e "\033[31m[ERREUR]\033[0m LXC $LXC_ID inexistant !"
    done

    if ! pct status "$LXC_ID" | grep -q "running"; then
        echo "Démarrage du LXC..."
        pct start "$LXC_ID"
        sleep 5
    fi
}

# Installation des paquets requis uniquement si absents
install_packages() {
    echo -e "\033[34m[INFO]\033[0m Vérification des paquets..."
    REQUIRED_PACKAGES=("openssh" "shadow" "openssh-sftp-server" "acl")
    MISSING_PACKAGES=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! pct exec "$LXC_ID" -- apk info "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done
    
    if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
        echo -e "\033[34m[INFO]\033[0m Installation des paquets manquants: ${MISSING_PACKAGES[*]}..."
        lxc_exec "apk update && apk add --no-cache ${MISSING_PACKAGES[*]}"
    else
        echo -e "\033[32m[OK]\033[0m Tous les paquets sont déjà installés."
    fi
}

# Configuration du groupe SFTP
setup_group() {
    echo -e "\033[34m[INFO]\033[0m Configuration du groupe SFTP..."
    lxc_exec "getent group ${SFTP_GROUP} || addgroup ${SFTP_GROUP}"
}

# Configuration SSH pour SFTP
setup_ssh() {
    echo -e "\033[34m[INFO]\033[0m Configuration de SSH pour SFTP..."
    if ! pct exec "$LXC_ID" -- grep -q "Match Group ${SFTP_GROUP}" /etc/ssh/sshd_config; then
        lxc_exec "echo -e '\n# Configuration SFTP\nSubsystem sftp internal-sftp\nMatch Group ${SFTP_GROUP}\n\tChrootDirectory %h\n\tForceCommand internal-sftp\n\tAllowTcpForwarding no' >> /etc/ssh/sshd_config"
        lxc_exec "rc-service sshd restart"
    fi
}

# Gestion des utilisateurs
manage_users() {
    while true; do
        read -rp "Nom utilisateur (laisser vide pour terminer) : " username
        [ -z "$username" ] && break

        password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
        if ! pct exec "$LXC_ID" -- id -u "$username" &>/dev/null; then
            read -rp "Chemin absolu pour $username : " userpath
            lxc_exec "mkdir -p '${userpath}'"
            lxc_exec "adduser -D -h '${userpath}' -s /sbin/nologin '${username}'"
            lxc_exec "adduser '${username}' '${SFTP_GROUP}'"
        else
            userpath=$(pct exec "$LXC_ID" -- getent passwd "$username" | cut -d: -f6)
            echo -e "\033[33m[INFO]\033[0m L'utilisateur $username existe déjà. Chemin utilisé : $userpath"
        fi

        lxc_exec "echo '${username}:${password}' | chpasswd"
        lxc_exec "chown root:root '${userpath}' && chmod 755 '${userpath}'"

        echo -e "\033[32m[SUCCÈS]\033[0m Utilisateur : ${username} | Mot de passe : ${password}"
    done
}

# Configuration réseau et redirection de port
setup_port_forward() {
    PORT=$((22000 + LXC_ID))
    IP="${LXC_NETWORK}.${LXC_ID}"
    echo -e "\033[34m[INFO]\033[0m Configuration de la redirection de port sur ${PORT}..."
    
    if ! iptables -t nat -C PREROUTING -i vmbr0 -p tcp --dport ${PORT} -j DNAT --to-destination ${IP}:22 &>/dev/null; then
        iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport ${PORT} -j DNAT --to-destination ${IP}:22
        iptables-save > /etc/iptables/rules.v4
    fi
}

# =============================================
# EXÉCUTION
# =============================================

echo -e "\033[36m[DÉMARRAGE]\033[0m Configuration SFTP en cours..."
verify_lxc
install_packages
setup_group
setup_ssh
manage_users
setup_port_forward
echo -e "\033[32m[TERMINÉ]\033[0m Configuration réussie !"

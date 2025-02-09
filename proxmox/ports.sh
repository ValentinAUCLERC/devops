#!/bin/bash

# Fichier de configuration des redirections
IPTABLES_PERSISTENT="/etc/iptables/rules.v4"

# Fonction pour générer l'interface graphique
show_menu() {
    clear
    echo "▐▀▄▀▌▐▀▄▀▌▐▀▄▀▌ Gestionnaire de ports Proxmox ▐▀▄▀▌▐▀▄▀▌▐▀▄▀▌"
    echo
    echo "Ports actuellement redirigés :"
    iptables -t nat -L PREROUTING -n --line-numbers | grep "dpt:22" | awk '{print $1") Port "substr($12,5)" → "$11}'
    echo
    echo "1) Ajouter une redirection manuelle"
    echo "2) Ajouter automatiquement (port 22XXX → LXC XXX)"
    echo "3) Supprimer une redirection"
    echo "4) Quitter"
    echo
    read -p "Choisissez une option : " choice
}

# Fonction pour ajouter une redirection manuelle
add_manual() {
    read -p "Port hôte (ex: 22100) : " host_port
    read -p "IP du LXC (ex: 10.0.0.100) : " lxc_ip
    add_forward "$host_port" "$lxc_ip"
}

# Fonction pour ajouter automatiquement
add_auto() {
    read -p "Port hôte (format 22XXX) : " host_port
    lxc_id="${host_port:2}"  # Extrait XXX depuis 22XXX
    lxc_ip="10.0.0.$lxc_id"  # Modifier selon votre schéma d'IP
    
    # Vérification de l'existence du LXC
    if ! pct list | grep -q "$lxc_id"; then
        echo "Erreur : Le LXC $lxc_id n'existe pas !"
        return
    fi
    
    add_forward "$host_port" "$lxc_ip"
}

# Fonction commune d'ajout
add_forward() {
    iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport "$1" -j DNAT --to-destination "$2":22
    iptables-save > "$IPTABLES_PERSISTENT"
    echo "✓ Redirection ajoutée : $1 → $2:22"
    sleep 2
}

# Fonction de suppression
delete_forward() {
    read -p "Numéro de ligne à supprimer : " line_num
    iptables -t nat -D PREROUTING "$line_num"
    iptables-save > "$IPTABLES_PERSISTENT"
    echo "✓ Redirection supprimée"
    sleep 2
}

# Menu principal
while true; do
    show_menu
    case $choice in
        1) add_manual ;;
        2) add_auto ;;
        3) delete_forward ;;
        4) exit ;;
        *) echo "Option invalide"; sleep 1 ;;
    esac
done

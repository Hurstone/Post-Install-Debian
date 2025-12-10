#!/usr/bin/env bash
# Script d'automatisation pour configurer une machine Debian.
# Usage:
#   sudo ./setup_debian.sh            -> installation standard
#   sudo ./setup_debian.sh --netbios  -> inclut la couche NetBIOS (winbind + samba + 'wins' dans nsswitch)

# Options de shell strictes :
# -e  : quitte à la première erreur
# -u  : erreur si variable non initialisée
# -o pipefail : propage l'erreur dans les pipelines
set -euo pipefail

# Variables globales :
# Force le mode non interactif pour éviter les prompts pendant apt-get
DEBIAN_FRONTEND=noninteractive
# Commande apt-get avec options :
# -y : répond "oui" automatiquement
# --no-install-recommends : évite les paquets recommandés (garde l'installation minimale)
# Dpkg::Use-Pty=0 : évite l'utilisation de pseudo-terminal
APT_GET="apt-get -y -o Dpkg::Use-Pty=0 --no-install-recommends"
# Nombre maximal de tentatives pour les opérations sujettes aux erreurs réseau
RETRY_MAX=3

# Fonctions de logs (INFO/WARN/ERR) avec couleurs pour lisibilité
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

# Vérifie que le script est exécuté en root (nécessaire pour apt et modifications système)
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être exécuté en tant que root (utilisez sudo)."
    exit 1
  fi
}

# Enveloppe de "retry" générique :
# Réessaie une commande jusqu'à RETRY_MAX fois avec pause de 3s entre tentatives.
retry() {
  local tries=0 cmd_rc=0
  while true; do
    if "$@"; then
      return 0
    fi
    cmd_rc=$?
    tries=$((tries+1))
    if [ "$tries" -ge "$RETRY_MAX" ]; then
      err "Échec après $RETRY_MAX tentatives: $* (code $cmd_rc)"
      return "$cmd_rc"
    fi
    warn "Commande échouée (tentative $tries/$RETRY_MAX). Nouvelle tentative dans 3s..."
    sleep 3
  done
}

# Mise à jour des index APT et mise à niveau des paquets
apt_update_upgrade() {
  log "Mise à jour des index APT..."
  retry $APT_GET update
  log "Mise à niveau du système..."
  retry $APT_GET upgrade
}

# Installation des paquets demandés
install_packages() {
  # Notes sur les paquets :
  # - openssh-server : serveur SSH (le paquet 'ssh' est le client)
  # - zip + unzip : gestion des archives ZIP
  # - mlocate : fournit 'locate' et 'updatedb'
  # - dnsutils : fournit 'dig' et utilitaires DNS
  # - net-tools : fournit ifconfig (ancien outil)
  local pkgs=(
    openssh-server
    ssh
    zip
    unzip
    nmap
    mlocate
    ncdu
    curl
    git
    screen
    dnsutils
    net-tools
    sudo
    lynx
  )
  log "Installation des paquets principaux..."
  retry $APT_GET install "${pkgs[@]}"
}

# Initialise la base d'index pour 'locate' via 'updatedb'
post_install_locate() {
  if command -v updatedb >/dev/null 2>&1; then
    log "Initialisation de la base 'locate' (updatedb)..."
    retry updatedb
  else
    warn "La commande 'updatedb' n'est pas disponible. Vérifiez l'installation de mlocate."
  fi
}

# Active et démarre le service SSH si disponible sous systemd
enable_services() {
  # Vérifie l'existence de l'unité ssh.service
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    log "Activation et démarrage du service SSH..."
    systemctl enable --now ssh || warn "Impossible d'activer/démarrer ssh. Vérifiez systemd."
  else
    warn "Service SSH introuvable dans systemd."
  fi
}

# Installe la couche NetBIOS et configure nsswitch pour 'wins'
install_netbios_stack() {
  log "Installation de la couche NetBIOS (winbind, samba)..."
  retry $APT_GET install winbind samba

  # Active les services liés si présents
  for svc in winbind smbd nmbd; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      log "Activation et démarrage du service ${svc}..."
      systemctl enable --now "$svc" || warn "Impossible d'activer/démarrer ${svc}."
    fi
  done

  # Ajout de 'wins' à la fin de la ligne 'hosts' dans /etc/nsswitch.conf
  local nss="/etc/nsswitch.conf"
  if [ -f "$nss" ]; then
    log "Ajout de 'wins' à la ligne 'hosts' dans $nss (si absent)..."
    # Sauvegarde avec horodatage pour rollback
    cp "$nss" "${nss}.bak.$(date +%Y%m%d%H%M%S)"
    # Vérifie qu'une ligne 'hosts' existe
    if grep -Eiq '^\s*hosts:' "$nss"; then
      # Évite les doublons si 'wins' déjà présent
      if grep -Eiq '^\s*hosts:.*\bwins\b' "$nss"; then
        warn "'wins' est déjà présent dans la ligne 'hosts'."
      else
        # Append 'wins' en fin de ligne tout en conservant le contenu
        sed -E -i 's/^(hosts:[[:space:]]+.*)$/\1 wins/' "$nss"
        log "'wins' ajouté à la ligne 'hosts'."
      fi
    else
      # Si la ligne 'hosts' n'existe pas, en crée une par défaut
      warn "Aucune ligne 'hosts' trouvée dans $nss. Ajout d'une ligne par défaut."
      printf "hosts: files mdns4_minimal [NOTFOUND=return] dns wins\n" >> "$nss"
    fi
  else
    err "$nss introuvable; impossible de configurer 'wins'."
  fi
}

# Personnalise le .bashrc root : décommente les lignes 9 à 13
customize_root_bashrc() {
  local bashrc="/root/.bashrc"
  if [ -f "$bashrc" ]; then
    log "Personnalisation de /root/.bashrc (décommenter lignes 9 à 13)..."
    # Sauvegarde du fichier avant modification
    cp "$bashrc" "${bashrc}.bak.$(date +%Y%m%d%H%M%S)"
    # Supprime un '#' (et espaces) au début des lignes 9 à 13
    # Attention : cela décommente tout début de ligne commenté dans cette plage
    sed -i '9,13{s/^[[:space:]]*#\s*//}' "$bashrc"
  else
    warn "$bashrc introuvable; aucune personnalisation appliquée."
  fi
}

# Point d'entrée principal
main() {
  require_root

  # Parsing des options du script (actuellement, seulement --netbios)
  local NETBIOS=0
  for arg in "${@:-}"; do
    case "$arg" in
      --netbios) NETBIOS=1 ;;                             # Active la configuration NetBIOS
      *)                                             # Option inconnue -> message d'aide
        err "Option inconnue: $arg"
        printf "Usage: %s [--netbios]\n" "$0"
        exit 2
        ;;
    esac
  done

  log "Démarrage de l'installation automatisée Debian."
  apt_update_upgrade          # Mise à jour et upgrade
  install_packages            # Installation des paquets
  post_install_locate         # Initialisation 'locate'
  enable_services             # Activation des services (SSH)

  # Branche optionnelle NetBIOS
  if [ "$NETBIOS" -eq 1 ]; then
    log "Mode local: configuration de la couche NetBIOS."
    install_netbios_stack
  else
    log "Couche NetBIOS non installée (utilisez --netbios pour l'activer sur machines locales non exposées)."
  fi

  customize_root_bashrc       # Décommenter .bashrc root (lignes 9 à 13)
  log "Installation terminée."
}

# Exécute la fonction main avec les arguments du script
main "$@"

#!/usr/bin/env bash
# Debian setup automation script (updated: Webmin + bsdgames)
# Usage:
#   sudo ./setup_debian.sh [--netbios] [--webmin] [--fun]
#   --netbios : installe winbind + samba et ajoute 'wins' dans /etc/nsswitch.conf
#   --webmin  : ajoute le dépôt Webmin, installe Webmin et démarre le service
#   --fun     : installe bsdgames (jeux en CLI) et indique comment les lancer

set -euo pipefail

DEBIAN_FRONTEND=noninteractive
APT_GET="apt-get -y -o Dpkg::Use-Pty=0 --no-install-recommends"
RETRY_MAX=3

log()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être exécuté en tant que root (utilisez sudo)."
    exit 1
  fi
}

# Réessaie la commande passée en argument jusqu'à RETRY_MAX tentatives
retry() {
  local tries=0 rc=0
  while true; do
    if "$@"; then
      return 0
    fi
    rc=$?
    tries=$((tries+1))
    if [ "$tries" -ge "$RETRY_MAX" ]; then
      err "Échec après $RETRY_MAX tentatives: $* (code $rc)"
      return "$rc"
    fi
    warn "Commande échouée (tentative $tries/$RETRY_MAX). Nouvelle tentative dans 3s..."
    sleep 3
  done
}

apt_update_upgrade() {
  log "Mise à jour des index APT..."
  retry $APT_GET update
  log "Mise à niveau du système..."
  retry $APT_GET upgrade
}

install_packages() {
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

post_install_locate() {
  if command -v updatedb >/dev/null 2>&1; then
    log "Initialisation de la base 'locate' (updatedb)..."
    retry updatedb
  else
    warn "La commande 'updatedb' n'est pas disponible. Vérifiez l'installation de mlocate."
  fi
}

enable_services() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    log "Activation et démarrage du service SSH..."
    systemctl enable --now ssh || warn "Impossible d'activer/démarrer ssh. Vérifiez systemd."
  else
    warn "Service SSH introuvable dans systemd."
  fi
}

install_netbios_stack() {
  log "Installation de la couche NetBIOS (winbind, samba)..."
  retry $APT_GET install winbind samba

  for svc in winbind smbd nmbd; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      log "Activation et démarrage du service ${svc}..."
      systemctl enable --now "$svc" || warn "Impossible d'activer/démarrer ${svc}."
    fi
  done

  local nss="/etc/nsswitch.conf"
  if [ -f "$nss" ]; then
    log "Sauvegarde de $nss"
    cp "$nss" "${nss}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -Eiq '^\s*hosts:' "$nss"; then
      if grep -Eiq '^\s*hosts:.*\bwins\b' "$nss"; then
        warn "'wins' est déjà présent dans la ligne 'hosts'."
      else
        sed -E -i 's/^(hosts:[[:space:]]+.*)$/\1 wins/' "$nss"
        log "'wins' ajouté à la ligne 'hosts'."
      fi
    else
      warn "Aucune ligne 'hosts' trouvée dans $nss. Ajout d'une ligne par défaut."
      printf "hosts: files mdns4_minimal [NOTFOUND=return] dns wins\n" >> "$nss"
    fi
  else
    err "$nss introuvable; impossible de configurer 'wins'."
  fi
}

# Installation de Webmin (optionnelle)
install_webmin() {
  log "Installation de Webmin (ajout du repo officiel puis installation)..."

  # Téléchargement du script d'ajout du dépôt Webmin dans un fichier temporaire
  local tmp_script="/tmp/webmin-setup-repo.sh"
  log "Téléchargement du script d'installation du dépôt Webmin..."
  # -f : fail silently on server errors, -sS : silencieux mais affiche erreurs, -L : suivre redirections
  if retry curl -fsSL -o "$tmp_script" "https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh"; then
    chmod +x "$tmp_script"
    log "Exécution du script d'ajout du dépôt Webmin..."
    # Exécute le script; il ajoute le dépôt et la clé GPG
    if retry sh "$tmp_script"; then
      log "Mise à jour des index APT après ajout du dépôt Webmin..."
      retry $APT_GET update
      log "Installation de Webmin (avec --install-recommends)..."
      retry $APT_GET install webmin --install-recommends
      # Activer et démarrer le service webmin si présent
      if systemctl list-unit-files | grep -q '^webmin\.service'; then
        log "Activation et démarrage du service webmin..."
        systemctl enable --now webmin || warn "Impossible d'activer/démarrer webmin via systemd."
      fi
      log "Webmin installé. Accès: https://<votre-ip-ou-FQDN>:10000"
    else
      err "Échec lors de l'exécution du script d'installation du dépôt Webmin."
    fi
  else
    err "Impossible de télécharger le script d'installation Webmin depuis GitHub."
  fi

  # Nettoyage du script temporaire
  rm -f "$tmp_script" || true
}

# Installation de bsdgames (optionnelle, 'fun')
install_bsdgames() {
  log "Installation de bsdgames (jeux en CLI)..."
  retry $APT_GET install bsdgames
  log "bsdgames installé. Les jeux se trouvent dans /usr/games."
  log "Pour lancer un jeu: cd /usr/games && ./nomdujeu"
}

customize_root_bashrc() {
  local bashrc="/root/.bashrc"
  if [ -f "$bashrc" ]; then
    log "Personnalisation de /root/.bashrc (décommenter lignes 9 à 13)..."
    cp "$bashrc" "${bashrc}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i '9,13{s/^[[:space:]]*#\s*//}' "$bashrc"
  else
    warn "$bashrc introuvable; aucune personnalisation appliquée."
  fi
}

main() {
  require_root

  local NETBIOS=0 WEBMIN=0 FUN=0
  for arg in "${@:-}"; do
    case "$arg" in
      --netbios) NETBIOS=1 ;;
      --webmin)  WEBMIN=1  ;;
      --fun)     FUN=1     ;;
      *) err "Option inconnue: $arg"; printf "Usage: %s [--netbios] [--webmin] [--fun]\n" "$0"; exit 2 ;;
    esac
  done

  log "Démarrage de l'installation automatisée Debian."
  apt_update_upgrade
  install_packages
  post_install_locate
  enable_services

  if [ "$NETBIOS" -eq 1 ]; then
    log "Mode local: configuration de la couche NetBIOS."
    install_netbios_stack
  else
    log "Couche NetBIOS non installée (utilisez --netbios pour l'activer)."
  fi

  if [ "$WEBMIN" -eq 1 ]; then
    install_webmin
  else
    log "Webmin non installé (utilisez --webmin pour l'activer)."
  fi

  if [ "$FUN" -eq 1 ]; then
    install_bsdgames
  else
    log "bsdgames non installé (utilisez --fun pour l'activer)."
  fi

  customize_root_bashrc
  log "Installation terminée."
}

main "$@"

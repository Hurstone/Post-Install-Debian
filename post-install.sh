#!/usr/bin/env bash
set -euo pipefail
# -e : quitte le script si une commande retourne une erreur
# -u : erreur si une variable non définie est utilisée
# -o pipefail : si une commande d'un pipeline échoue, le pipeline échoue

# Usage: sudo ./post-install.sh [--network|-n]
WIZARD=0           # indicateur pour activer le "wizard réseau" (non implémenté ici)

# Boucle de traitement des arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--network) WIZARD=1; shift ;;        # active le mode wizard réseau
    *) echo "Unknown arg: $1"; exit 1 ;;    # argument inconnu -> sortie
  esac
done

# Vérification d'exécution en root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

# Fonction utilitaire : sauvegarde d'un fichier avant modification
backup() {
  if [[ -e "$1" ]]; then
    cp -a "$1" "$1.bak.$(date +%s)"
    # cp -a préserve les permissions ; on ajoute un suffixe horodaté pour rollback
  fi
}

echo "=== Mise à jour du système ==="
# Mise à jour des listes de paquets et mise à niveau automatique
apt update && apt upgrade -y

echo "=== Installation des paquets de base ==="
# Installation des outils usuels pour administration et diagnostic
apt install -y ssh zip nmap locate ncdu curl git screen dnsutils net-tools sudo lynx

echo "=== Installation Samba et Winbind ==="
# Samba fournit le partage SMB/CIFS ; winbind permet l'intégration d'annuaires (ex: AD)
apt install -y samba winbind

# Note: la configuration NetBIOS/WINS n'est plus modifiée automatiquement.
# Si vous avez besoin d'activer NetBIOS local, modifiez /etc/samba/smb.conf manuellement.

# Modifier /etc/nsswitch.conf : ajouter 'wins' à la fin de la ligne hosts si absent
NSS=/etc/nsswitch.conf
backup "$NSS"   # sauvegarde avant modification
if grep -q '^hosts:' "$NSS"; then
  if ! grep -q '^hosts:.*\bwins\b' "$NSS"; then
    # Ajoute 'wins' à la fin de la ligne hosts (sécurisé si la ligne existe)
    sed -i 's/^\(hosts:.*\)$/\1 wins/' "$NSS"
    echo "Ajout de 'wins' à /etc/nsswitch.conf"
  else
    echo "'wins' déjà présent dans /etc/nsswitch.conf"
  fi
else
  # Si la ligne hosts: n'existe pas, on avertit l'administrateur
  echo "Aucune ligne 'hosts:' trouvée dans $NSS — vérifiez manuellement." >&2
fi

# Personnalisation du BASH root : décommenter lignes 9-13 si elles existent
BASHRC=/root/.bashrc
backup "$BASHRC"   # sauvegarde du .bashrc root
if [[ -f "$BASHRC" ]]; then
  total_lines=$(wc -l < "$BASHRC")
  if (( total_lines >= 9 )); then
    # Pour chaque ligne 9 à 13, si elle commence par '#', on enlève le '#'
    for i in $(seq 9 14); do
      if sed -n "${i}p" "$BASHRC" | grep -q '^#'; then
        sed -i "${i}s/^#//" "$BASHRC" || true
      fi
    done
    echo "Lignes 9-14 de $BASHRC traitées (décommentées si présentes)."
  else
    # Si le fichier est trop court, on ne tente pas de décommenter
    echo "$BASHRC a moins de 9 lignes, aucune modification effectuée."
  fi
else
  # Si /root/.bashrc n'existe pas, on crée un fichier minimal pour éviter erreurs futures
  echo "$BASHRC introuvable, création d'un fichier minimal."
  cat > "$BASHRC" <<'EOF'
# /root/.bashrc minimal
PS1='\u@\h:\w\$ '
EOF
fi

# Installation Webmin : téléchargement sécurisé du script d'ajout de repo puis installation
WEBMIN_SCRIPT_URL="https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh"
TMP_SCRIPT="/tmp/webmin-setup-repo.sh"

echo "=== Téléchargement du script d'installation Webmin ==="
# curl -fsSL : -f échoue sur codes HTTP >=400 ; -s silence ; -S affiche erreur si échec ; -L suit redirections
if curl -fsSL -o "$TMP_SCRIPT" "$WEBMIN_SCRIPT_URL"; then
  # Vérifier que le fichier téléchargé n'est pas du HTML (page d'erreur)
  if grep -qi "<!doctype\|<html" "$TMP_SCRIPT"; then
    # Si HTML détecté, on supprime le fichier et on signale l'erreur
    echo "Erreur : le fichier téléchargé semble être du HTML. Abandon." >&2
    echo "Vérifiez l'URL ou la connectivité réseau." >&2
    rm -f "$TMP_SCRIPT"
  else
    # Rendre exécutable et exécuter le script d'ajout du dépôt Webmin
    chmod +x "$TMP_SCRIPT"
    echo "Exécution du script Webmin..."
    sh "$TMP_SCRIPT"
    # Mise à jour des listes et installation du paquet webmin
    apt update
    apt install -y webmin --install-recommends
    echo "Webmin installé. Accessible sur https://<IP-ou-FQDN>:10000"
  fi
else
  # Si curl a échoué, on l'indique (ex: pas d'accès réseau ou URL invalide)
  echo "Échec du téléchargement du script Webmin (curl a retourné une erreur)." >&2
fi

# Bonus : bsdgames (jeux classiques)
echo "=== Installation bsdgames (bonus) ==="
apt install -y bsdgames || true
# On ignore l'erreur éventuelle pour ne pas casser le reste du script

echo "=== Terminé ==="
if [[ $WIZARD -eq 1 ]]; then
  echo "Le mode wizard réseau a été demandé mais n'est pas encore implémenté dans ce script."
  echo "Répondez aux questions demandées pour que j'ajoute la configuration réseau automatique."
fi

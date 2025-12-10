#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo ./postinstall.sh [--network|-n] [--local-netbios]
WIZARD=0
LOCAL_NETBIOS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--network) WIZARD=1; shift ;;
    --local-netbios) LOCAL_NETBIOS=1; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"; exit 1
fi

backup() {
  cp -a "$1" "$1.bak.$(date +%s)" || true
}

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing base packages..."
apt install -y ssh zip nmap locate ncdu curl git screen dnsutils net-tools sudo lynx

echo "Installing Samba and Winbind..."
apt install -y samba winbind

if [[ $LOCAL_NETBIOS -eq 1 ]]; then
  echo "Enabling NetBIOS/SMB name resolution (local only)..."
  # smbclient / nmbd are provided by samba package; ensure nmbd enabled in smb.conf if needed
  sed -i '/

\[global\]

/a \ \ \ \ name resolve order = wins lmhosts host bcast' /etc/samba/smb.conf || true
fi

# Modify /etc/nsswitch.conf to add 'wins' at end of hosts line if missing
NSS=/etc/nsswitch.conf
backup "$NSS"
if ! grep -q '^hosts:.*wins' "$NSS"; then
  sed -i 's/^\(hosts:.*\)$/\1 wins/' "$NSS"
fi

# Personalize root bash: uncomment lines 9-13 in /root/.bashrc (backup first)
BASHRC=/root/.bashrc
backup "$BASHRC"
# Safely uncomment lines 9-13 if they exist
nl -ba "$BASHRC" | sed -n '9,13p' >/dev/null 2>&1 || true
for i in {9..13}; do
  sed -i "${i}s/^#//" "$BASHRC" || true
done

# Install Webmin (repo script + apt install)
echo "Installing Webmin repository and package..."
curl -o /tmp/webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
sh /tmp/webmin-setup-repo.sh
apt update
apt install -y webmin --install-recommends

# Bonus: bsdgames
apt install -y bsdgames

echo "Done. Webmin available at https://<IP-or-FQDN>:10000 (port 10000)."

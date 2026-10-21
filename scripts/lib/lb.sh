#!/usr/bin/env bash
# Provisionnement du répartiteur HAProxy (idempotent)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

NOEUDS=/vagrant/config/noeuds.yml
TPL=/vagrant/config/haproxy.cfg.tpl
CFG=/etc/haproxy/haproxy.cfg
PORT="${APP_PORT:-3000}"

# 1. Installation (seulement si absent)
if ! command -v haproxy >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq haproxy
fi

# 2. Une ligne "server" par noeud de role "app", lue dans noeuds.yml
tr -d '\r' < "$NOEUDS" | awk -v port="$PORT" '
  /^- nom:/  { nom = $3 }
  /^  ip:/   { ip = $2 }
  /^  role:/ { if ($2 == "app") printf "    server %s %s:%s check\n", nom, ip, port }
' > /tmp/serveurs.txt

if [ ! -s /tmp/serveurs.txt ]; then
  echo "ERREUR : aucun serveur applicatif trouve dans $NOEUDS" >&2
  exit 1
fi

# 3. Génération de la configuration à partir du modèle
sed -e '/__SERVEURS__/{r /tmp/serveurs.txt' -e 'd}' "$TPL" > /tmp/haproxy.cfg.new

# 4. Validation puis application, seulement si le contenu a changé
haproxy -c -q -f /tmp/haproxy.cfg.new
if ! cmp -s /tmp/haproxy.cfg.new "$CFG"; then
  cp /tmp/haproxy.cfg.new "$CFG"
  systemctl reload haproxy 2>/dev/null || systemctl restart haproxy
  echo "lb : configuration mise a jour"
else
  echo "lb : configuration inchangee"
fi

systemctl enable --now haproxy
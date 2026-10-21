#!/usr/bin/env bash
# RÉSULTATS-BF — serveur applicatif sans état (R3).
# Aucune dépendance à la base au démarrage : les connexions sont ouvertes
# à la demande. Une base absente au démarrage n'empêche pas le service
# de démarrer ; elle ne renvoie que 503 le temps de la panne (piège n°4).

. /tmp/lib.sh

PORT="${APP_PORT:-3000}"
IP_BDD1="$(tr -d '\r' < /tmp/noeuds.tsv | awk -F'\t' '$3 == "bdd" { print $2; exit }')"

log "installation du service applicatif (python3 + psycopg2)"
apt_install python3 python3-psycopg2

id resultats >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin resultats
install -d -o resultats -g resultats /opt/resultats-bf
install -o resultats -g resultats -m 0644 /tmp/app.py /opt/resultats-bf/app.py

# Configuration : la base primaire est la cible initiale. En cas de bascule,
# scripts/bascule.sh réécrit DB_HOST dans ce fichier et relance le service (R6).
# Réécrit seulement s'il n'existe pas : une bascule déjà faite n'est pas annulée
# par un « vagrant provision ».
if [ ! -f /etc/default/resultats ]; then
  cat > /etc/default/resultats <<EOF
DB_HOST=${IP_BDD1}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
APP_PORT=${PORT}
EOF
  chmod 600 /etc/default/resultats
fi

ecrire_si_different /etc/systemd/system/resultats.service <<'EOF' || true
[Unit]
Description=RÉSULTATS-BF — service applicatif sans état
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=resultats
Group=resultats
EnvironmentFile=/etc/default/resultats
ExecStart=/usr/bin/python3 /opt/resultats-bf/app.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now resultats
systemctl restart resultats
attente 15 bash -c "curl -sf -o /dev/null http://127.0.0.1:${PORT}/info"
log "app OK — écoute 0.0.0.0:${PORT}"

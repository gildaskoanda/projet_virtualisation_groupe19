#!/usr/bin/env bash
# RÉSULTATS-BF — obs : supervision (extension E2).
# Prometheus collecte node_exporter (tous les nœuds, installé par base.sh)
# ainsi que les métriques natives de HAProxy (front :8404). Grafana arrive
# avec une source de données et un tableau de bord provisionnés : aucun
# clic manuel n'est nécessaire pour reproduire l'installation.

. /tmp/lib.sh

log "installation de Prometheus + ab (outil de charge)"
apt_install prometheus apache2-utils

log "ajout du dépôt officiel Grafana"
apt_install wget gnupg ca-certificates
if [ ! -f /etc/apt/keyrings/grafana.gpg ]; then
  install -d -m 0755 /etc/apt/keyrings
  wget -qO- https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list
  apt-get update -qq
fi
apt_install grafana

# Cibles de collecte engendrées depuis la table des nœuds (R3).
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: node
    static_configs:
EOF
awk -F'\t' '{ printf "      - targets: [\"%s:9100\"]\n        labels: { nom: \"%s\" }\n", $2, $1 }' \
  /tmp/noeuds.tsv >> /etc/prometheus/prometheus.yml
{
  echo "  - job_name: haproxy"
  echo "    static_configs:"
  echo -n "      - targets: ["
  awk -F'\t' '$3 == "lb" { printf "\"%s:8404\",", $2 }' /tmp/noeuds.tsv | sed 's/,$//'
  echo "]"
} >> /etc/prometheus/prometheus.yml

promtool check config /etc/prometheus/prometheus.yml

# Grafana : source de données et tableau de bord provisionnés (E2).
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

cat > /etc/grafana/provisioning/dashboards/resultats.yml <<'EOF'
apiVersion: 1
providers:
  - name: resultats-bf
    folder: ""
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

install -d -o grafana -g grafana /var/lib/grafana/dashboards
install -o grafana -g grafana -m 0644 /tmp/dashboard.json /var/lib/grafana/dashboards/resultats-bf.json

if [ -n "${GRAFANA_MDP:-}" ]; then
  sed -i "s/^;admin_password =.*/admin_password = ${GRAFANA_MDP}/" /etc/grafana/grafana.ini
fi

systemctl enable --now grafana-server prometheus
systemctl restart grafana-server prometheus

log "obs OK — Grafana sur http://${IP}:3000 (utilisateur admin, mot de passe dans .env)"

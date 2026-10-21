#!/usr/bin/env bash
# RÉSULTATS-BF — répartiteur de charge (lb1 ET lb2 : même script, une
# seule configuration engendrée depuis config/noeuds.tsv — R3).
#
# R4 : sonde /sante sur chaque serveur, éjection en quelques secondes (moins
# de 5 s exigées). Interdiction du cahier des charges respectée : AUCUNE
# adresse applicative n'est écrite en dur ici, tout vient de la source de
# vérité unique engendrée par le Vagrantfile.

. /tmp/lib.sh

: "${VRRP_PASS:?VRRP_PASS absent (fichier .env)}"

log "installation de HAProxy + keepalived"
apt_install haproxy keepalived

# Réponse 503 propre en JSON (V4 : jamais de page blanche ni d'erreur brute).
mkdir -p /etc/haproxy/erreurs
printf 'HTTP/1.0 503 Service Unavailable\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-Type: application/json\r\n\r\n{"erreur":"service indisponible","detail":"aucun serveur applicatif en etat"}\r\n' \
  > /etc/haproxy/erreurs/503.http

# Paramètres relus par rafraichir-haproxy, aussi appelé hors provisionnement.
ecrire_si_different /etc/default/resultats-lb <<EOF || true
APP_PORT=${APP_PORT:-3000}
EOF

# Génération + rechargement à chaud : réutilisé par le déclencheur Vagrant
# (R3) et par la procédure d'ajout d'un serveur, sans jamais couper le trafic.
# La configuration n'est remplacée (et HAProxy rechargé) que si elle change,
# et seulement après validation : jamais de configuration cassée sur disque.
cat > /usr/local/sbin/rafraichir-haproxy <<'GEN'
#!/usr/bin/env bash
set -euo pipefail
. /etc/default/resultats-lb
LISTE_APP="$(tr -d '\r' < /tmp/noeuds.tsv | awk -F'\t' '$3 == "app" { print $1, $2 }')"
[ -n "$LISTE_APP" ] || { echo "rafraichir-haproxy : aucune app dans noeuds.tsv" >&2; exit 1; }
NOUVEAU="$(mktemp)"
cat > "$NOUVEAU" <<EOF
global
    log         /dev/log local0
    maxconn     2000
    user        haproxy
    group       haproxy
    daemon

defaults
    log         global
    mode        http
    option      httplog
    option      dontlognull
    option      forwardfor
    option      redispatch
    retries     2
    timeout connect 1s
    timeout check   1s
    timeout client  30s
    timeout server  30s

frontend http_front
    bind *:80
    default_backend apps

# Front de métriques pour Prometheus (extension E2) — interne uniquement.
frontend metrics
    bind *:8404
    http-request use-service prometheus-exporter if { path /metrics }

backend apps
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
    default-server inter 1s fastinter 500ms downinter 2s fall 2 rise 2
EOF
while read -r nom ip; do
  echo "    server ${nom} ${ip}:${APP_PORT} check" >> "$NOUVEAU"
done <<< "$LISTE_APP"
echo "    errorfile 503 /etc/haproxy/erreurs/503.http" >> "$NOUVEAU"
haproxy -c -q -f "$NOUVEAU"
if cmp -s "$NOUVEAU" /etc/haproxy/haproxy.cfg; then
  echo "haproxy : configuration inchangee"
else
  install -m 0644 "$NOUVEAU" /etc/haproxy/haproxy.cfg
  systemctl reload haproxy 2>/dev/null || systemctl restart haproxy
  echo "haproxy : configuration mise a jour"
fi
rm -f "$NOUVEAU"
GEN
chmod 0755 /usr/local/sbin/rafraichir-haproxy
/usr/local/sbin/rafraichir-haproxy
systemctl enable --now haproxy

# keepalived (E1) : les deux répartiteurs partagent la VIP ; lequel des
# deux la porte dépend de la priorité et de l'état de HAProxy local.
# Le mot de passe VRRP vient de .env (R7) ; keepalived le limite à 8 caractères.
VIP="$(tr -d '\r' < /tmp/noeuds.tsv | awk -F'\t' -v moi="$(hostname -s)" '$1 == moi { print $4 }')"
PRIO="$(tr -d '\r' < /tmp/noeuds.tsv | awk -F'\t' -v moi="$(hostname -s)" '$1 == moi { print $5 }')"
IFACE="$(ip -o -4 addr show | awk -v plage="${IP%.*}." '$4 ~ "^" plage { print $2; exit }')"
if ecrire_si_different /etc/keepalived/keepalived.conf 0600 <<EOF
vrrp_script check_haproxy {
    script "/usr/bin/pgrep -x haproxy"
    interval 1
    fall 2
    rise 2
}

vrrp_instance VI_RESULTATS {
    state            BACKUP
    interface        ${IFACE}
    virtual_router_id 51
    priority         ${PRIO}
    advert_int       1
    authentication {
        auth_type PASS
        auth_pass ${VRRP_PASS:0:8}
    }
    virtual_ipaddress {
        ${VIP}/24
    }
    track_script {
        check_haproxy
    }
}
EOF
then
  systemctl enable keepalived
  systemctl restart keepalived
  log "keepalived : configuration mise a jour"
else
  systemctl enable --now keepalived
  log "keepalived : configuration inchangee"
fi

attente 20 bash -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/sante | grep -qE "200|503"'
log "lb OK — VIP ${VIP} (priorité ${PRIO})"

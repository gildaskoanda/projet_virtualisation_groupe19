#!/usr/bin/env bash
# RÉSULTATS-BF — répartiteur de charge (lb1 ET lb2 : même script, une
# seule configuration engendrée depuis config/noeuds.tsv — R3).
#
# R4 : sonde /sante sur chaque serveur, inter 2 s, fall 2 → éjection en
# moins de 5 secondes. Interdiction du cahier des charges respectée :
# AUCUNE adresse applicative n'est écrite en dur ici, tout vient de la
# source de vérité unique engendrée par le Vagrantfile.

. /tmp/lib.sh

log "installation de HAProxy + keepalived"
apt_install haproxy keepalived

# Réponse 503 propre en JSON (V4 : jamais de page blanche ni d'erreur brute).
mkdir -p /etc/haproxy/erreurs
printf 'HTTP/1.0 503 Service Unavailable\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-Type: application/json\r\n\r\n{"erreur":"service indisponible","detail":"aucun serveur applicatif en etat"}\r\n' \
  > /etc/haproxy/erreurs/503.http

# Génération + rechargement à chaud : réutilisé par le déclencheur Vagrant
# (R3) et par la procédure d'ajout d'un serveur, sans jamais couper le trafic.
cat > /usr/local/sbin/rafraichir-haproxy <<'GEN'
#!/usr/bin/env bash
set -euo pipefail
LISTE_APP="$(awk -F'\t' '$3 == "app" { print $2 }' /tmp/noeuds.tsv)"
[ -n "$LISTE_APP" ] || { echo "rafraichir-haproxy : aucune app dans noeuds.tsv" >&2; exit 1; }
cat > /etc/haproxy/haproxy.cfg <<EOF
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
    timeout connect 3s
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
    default-server inter 2s fall 2 rise 2
EOF
for ip in $LISTE_APP; do
  echo "    server app_${ip//./_} ${ip}:8080 check" >> /etc/haproxy/haproxy.cfg
done
echo "errorfile 503 /etc/haproxy/erreurs/503.http" >> /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null
systemctl reload haproxy 2>/dev/null || systemctl restart haproxy
GEN
chmod 0755 /usr/local/sbin/rafraichir-haproxy
/usr/local/sbin/rafraichir-haproxy
systemctl enable --now haproxy

# keepalived (E1) : les deux répartiteurs partagent la VIP ; lequel des
# deux la porte dépend de la priorité et de l'état de HAProxy local.
VIP="$(awk -F'\t' -v moi="$(hostname -s)" '$1 == moi { print $4 }' /tmp/noeuds.tsv)"
PRIO="$(awk -F'\t' -v moi="$(hostname -s)" '$1 == moi { print $5 }' /tmp/noeuds.tsv)"
IFACE="$(ip -o -4 addr show | awk -v plage="${IP%.*}." '$4 ~ "^" plage { print $2; exit }')"
cat > /etc/keepalived/keepalived.conf <<EOF
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
        auth_pass rbf2026
    }
    virtual_ipaddress {
        ${VIP}/24
    }
    track_script {
        check_haproxy
    }
}
EOF
systemctl enable --now keepalived
systemctl restart keepalived

attente 20 bash -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/sante | grep -qE "200|503"'
log "lb OK — VIP ${VIP} (priorité ${PRIO})"

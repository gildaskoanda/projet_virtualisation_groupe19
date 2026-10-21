#!/usr/bin/env bash
# RÉSULTATS-BF — bdd2 : réplique en flux de bdd1 (R5).
# Le basebackup n'est refait que si la machine n'est pas déjà configurée
# en réplique : le re-provisionnement est sans effet (R2).

. /tmp/lib.sh

PG_MAJOR=16
DATA="/var/lib/postgresql/${PG_MAJOR}/main"
AUTOCONF="/etc/postgresql/${PG_MAJOR}/main/postgresql.auto.conf"

IP_BDD1="$(awk -F'\t' '$3 == "bdd" { print $2; exit }' /tmp/noeuds.tsv)"
log "réplication en flux depuis ${IP_BDD1}"

apt_install postgresql postgresql-contrib
systemctl stop postgresql

if grep -qs 'primary_conninfo' "$AUTOCONF" && [ -f "$DATA/PG_VERSION" ]; then
  log "déjà réplique — basebackup ignoré (idempotence)"
else
  rm -rf "$DATA"
  mkdir -p "$DATA"
  chown postgres:postgres "$DATA"
  chmod 700 "$DATA"

  log "attente de la primaire, puis basebackup (-R = standby + conninfo)"
  attente 90 bash -c "pg_isready -h ${IP_BDD1} -p 5432" || { log "bdd1 injoignable"; exit 1; }
  attente 90 env PGPASSWORD="${DB_REPL_PASSWORD}" \
    pg_basebackup -h "${IP_BDD1}" -U "${DB_REPL_USER}" -D "${DATA}" -R -X stream
  chown -R postgres:postgres "$DATA"
fi

pg_conftool "$PG_MAJOR" main set listen_addresses "'${IP}'"
systemctl start postgresql

attente 30 bash -c "pg_isready -h ${IP} -p 5432"
if sudo -u postgres psql -tAc "SELECT pg_is_in_recovery()" | grep -q t; then
  log "bdd2 OK — réplique en lecture (hot standby)"
else
  log "ATTENTION : bdd2 n'est pas en mode recovery — vérifier la réplication"
  exit 1
fi

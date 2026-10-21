#!/usr/bin/env bash
# RÉSULTATS-BF — bdd2 : réplique en flux de bdd1 (R5).
# Le basebackup n'est fait qu'une seule fois (fichier témoin) : un
# re-provisionnement est sans effet (R2) et n'efface JAMAIS une réplique
# déjà promue en primaire après une bascule (R6).

. /tmp/lib.sh

PG_MAJOR=16
DATA="/var/lib/postgresql/${PG_MAJOR}/main"
CONF_D="/etc/postgresql/${PG_MAJOR}/main/conf.d"
HBA="/etc/postgresql/${PG_MAJOR}/main/pg_hba.conf"
TEMOIN="/var/lib/postgresql/.replique-initialisee"
changement=0

IP_BDD1="$(tr -d '\r' < /tmp/noeuds.tsv | awk -F'\t' '$3 == "bdd" { print $2; exit }')"
log "réplication en flux depuis ${IP_BDD1}"

apt_install postgresql postgresql-contrib

if ecrire_si_different "${CONF_D}/resultats.conf" <<EOF
listen_addresses = '${IP}'
wal_level = replica
max_wal_senders = 5
EOF
then
  changement=1
fi

# pg_hba.conf n'est PAS copié par pg_basebackup (il vit dans /etc) : sans ces
# lignes, les applications seraient refusées par bdd2 après la promotion (V4).
if ! grep -q '# resultats-bf' "$HBA"; then
  cat >> "$HBA" <<EOF
# resultats-bf — accès autorisés sur le réseau privé uniquement
host    ${DB_NAME}        ${DB_USER}        ${RESEAU}.0/24        scram-sha-256
host    replication       ${DB_REPL_USER}   ${RESEAU}.31/32       scram-sha-256
EOF
  changement=1
fi

basebackup() {
  find "$DATA" -mindepth 1 -delete
  PGPASSWORD="${DB_REPL_PASSWORD}" pg_basebackup \
    -h "${IP_BDD1}" -U "${DB_REPL_USER}" -D "${DATA}" -R -X stream
}

if [ -f "$TEMOIN" ]; then
  log "déjà initialisée comme réplique — basebackup ignoré (idempotence)"
else
  systemctl stop postgresql
  mkdir -p "$DATA"
  chown postgres:postgres "$DATA"
  chmod 700 "$DATA"
  log "attente de la primaire, puis basebackup (-R = standby + conninfo)"
  attente 90 pg_isready -q -h "${IP_BDD1}" -p 5432 || { log "bdd1 injoignable"; exit 1; }
  attente 90 basebackup || { log "basebackup impossible"; exit 1; }
  chown -R postgres:postgres "$DATA"
  chmod 700 "$DATA"
  touch "$TEMOIN"
  changement=1
fi

systemctl enable postgresql
if pg_isready -q -h "$IP" -p 5432; then
  if [ "$changement" = 1 ]; then
    systemctl restart postgresql
  fi
else
  systemctl start postgresql
fi
attente 30 pg_isready -q -h "$IP" -p 5432

if sudo -u postgres psql -tAc "SELECT pg_is_in_recovery()" | grep -q t; then
  log "bdd2 OK — réplique en lecture (hot standby)"
else
  log "bdd2 OK — déjà promue en primaire (bascule effectuée)"
fi

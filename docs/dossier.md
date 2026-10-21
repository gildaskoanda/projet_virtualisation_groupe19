# Dossier d'architecture — RÉSULTATS-BF

> Document de référence du groupe 19. Les cases `[À MESURER]` seront
> remplies par les résultats des scénarios `tests/v1…v6` exécutés sur le
> poste de développement.

## 1. Contexte et mandat

Chaque année, la publication des résultats d'examens fait tomber le site
dans les dix minutes suivant l'annonce. Le groupe est mandaté pour
construire la plateforme RÉSULTATS-BF : consultation d'un résultat à
partir d'un matricule, avec deux exigences non fonctionnelles primaires —
**résilience** (la panne d'une machine n'interrompt pas le service) et
**scalabilité** (ajouter du trafic = ajouter des machines, sans réécrire
la configuration). L'intégralité de l'infrastructure est décrite en code
et se reconstruit d'un seul geste : `vagrant destroy -f && vagrant up`.

## 2. Des exigences aux choix d'architecture

| Exigence | Choix | Justification |
|----------|-------|---------------|
| Résilience applicative | serveurs **sans état** derrière HAProxy à sonde active | aucun état local ⇒ retirer un serveur est indolore ; la sonde `/sante` réelle (SELECT 1) ne peut pas renvoyer 200 « par principe » |
| Résilience base | réplication en flux PostgreSQL + bascule scriptée | la donnée est le seul état du système ; elle doit survivre à la panne de la primaire |
| Résilience répartiteur (E1) | keepalived/VRRP, deux HAProxy identiques, VIP partagée | le répartiteur est le point de défaillance unique naturel — on le supprime en le doublant |
| Scalabilité | table `NOEUDS` unique dans le Vagrantfile engendrant `config/noeuds.tsv` | une seule source de vérité : la configuration du répartiteur et de la supervision dérive du même tableau que les machines. « Scalable » sans cela n'est qu'un mot |
| Re productibilité | provisionnement shell idempotent, secrets hors dépôt, boîte épinglée, dossier synchronisé désactivé | R1/R2/R7 ; aucun geste manuel, aucun secret, aucun écart entre postes |
| Observabilité (E2) | Prometheus + node_exporter partout + métriques natives HAProxy + Grafana provisionné | « mesurer plutôt qu'affirmer » : débit, état des serveurs, disparition visible d'une machine en panne |

## 3. Architecture

### 3.1 Inventaire des machines

| Machine | Rôle | Adresse | RAM |
|---------|------|---------|-----|
| lb1 | HAProxy actif + keepalived | 192.168.XX.11 | 512 Mo |
| lb2 | HAProxy passif + keepalived (E1) | 192.168.XX.12 | 512 Mo |
| app1…appN | service Python sans état, :3000 | .21 … .2N | 512 Mo |
| bdd1 | PostgreSQL 16 primaire | .31 | 768 Mo |
| bdd2 | réplique en flux (hot standby) | .32 | 768 Mo |
| obs | Prometheus + Grafana + ab | .41 | 768 Mo |
| **VIP** | adresse flottante VRRP | .5 | — |

Sous-réseau : `192.168.58.0/24` (règle `X = 55 + G` avec G = 3 : notre groupe
porte le numéro 19, hors de la plage 1 à 8 prévue par le sujet). Plage imposée
par VirtualBox ≥ 6.1.28 : 192.168.56.0–63.255.

### 3.2 Schéma

```
        Hôte
         │ :8080 (seul port transféré, R8)
         ▼
   ┌──────────┐   VRRP VIP .5     ┌──────────┐
   │   lb1    │◄─────────────────►│   lb2    │
   │ HAProxy  │   keepalived      │ HAProxy  │
   └────┬─────┘                   └────┬─────┘
        │ sonde /sante toutes les 2 s  │
   ┌────┴─────────┬────────────────────┴────┐
   ▼              ▼                         ▼
 app1:3000 … appN:3000                 obs:9090/3000
   │ SELECT / INSERT                      │ scrape :9100, :8404
   ▼                                      ▼
 bdd1:5432 ── réplication en flux ──► bdd2:5432   Prometheus+Grafana
```

### 3.3 Source unique de vérité (R3)

La table `NOEUDS` du `Vagrantfile` décrit chaque machine (nom, IP, RAM,
rôle, VIP, priorité VRRP) et engendre `config/noeuds.tsv`. C'est ce
fichier que lisent `rafraichir-haproxy` (liste des backends), `obs.sh`
(cibles de Prometheus) et `bascule.sh` (VIP, liste des apps). Aucune
adresse applicative n'est écrite en dur ailleurs — sous peine de 2 points
de pénalité. Passer de 2 à 4 serveurs : `NB_APP=4 vagrant up` — un
déclencheur Vagrant pousse le `noeuds.tsv` à jour et recharge HAProxy à
chaud (`reload`, sans coupure).

## 4. Détail technique

### 4.1 Application (`app/app.py`, moins de 100 lignes)

Python 3 + psycopg2, `ThreadingHTTPServer` sur `0.0.0.0:3000`. Trois
routes : `/resultat?matricule=` (JSON), `/sante` (200 si `SELECT 1`
réussit, 503 sinon — jamais 200 par principe), `/info` (hôte).
**Aucun état local** : chaque requête ouvre sa connexion. Une base
absente au démarrage ne bloque donc rien : le service démarre et renvoie
503 le temps de la panne (piège n°4 du cahier des charges).

### 4.2 Provisionnement idempotent (R2)

Chaque script rejouable : gardes `grep -q ||` avant toute ligne
ajoutée (pg_hba), fichiers de configuration comparés puis écrits
seulement s'ils changent (`ecrire_si_different`), services redémarrés
seulement en cas de changement, `CREATE TABLE IF NOT EXISTS` et jeu de
données inséré une seule fois (50 000 lignes déterministes),
basebackup de bdd2 protégé par un fichier témoin : un
re-provisionnement n'efface jamais une réplique promue. `vagrant provision` rejoué deux fois de suite ne
modifie rien et n'échoue pas.

### 4.3 Réplication et bascule (R5, R6)

bdd1 : `wal_level=replica`, rôle `replique` avec `REPLICATION`, pg_hba
limité au réseau privé (`bdd2/32` pour la réplication). bdd2 reçoit les
mêmes règles pour les applications : `pg_hba.conf` n'est pas copié par
`pg_basebackup`, sans elles bdd2 refuserait les applications après la
promotion. bdd2 : `pg_basebackup -R -X stream` (standby.signal
+ primary_conninfo), `hot_standby` actif. Bascule
(`scripts/bascule.sh`, chronométrée) : promotion de bdd2
(`pg_ctlcluster promote`), passage de `DB_HOST` vers bdd2 sur chaque app
(fichier `/etc/default/resultats`), redémarrage des services, vérification
de `/sante` via la VIP. Temps total mesuré : `[À MESURER]` s.

### 4.4 Répartiteur (R4)

HAProxy généré par `rafraichir-haproxy` depuis `noeuds.tsv` :
`balance roundrobin`, `option httpchk GET /sante`,
`http-check expect status 200`, `default-server inter 1s fastinter 500ms fall 2 rise 2`,
`timeout connect 1s`, `timeout check 1s`, `option redispatch`
→ éjection attendue en 3 à 4 s (< 5 s exigé), à confirmer par la mesure V2. Réponse 503 en JSON via
`errorfile` (V4 : jamais de page blanche). Front métriques :8404
(`prometheus-exporter`) pour E2.

### 4.5 Redondance VRRP (E1)

lb1 et lb2 exécutent la **même** HAProxy et le **même** keepalived
(`state BACKUP`, priorités 110/100, `vrrp_script` sur `pgrep haproxy`,
VIP `XX.5/24`, mot de passe VRRP lu dans `.env`). Bascule ≤ 5 s si lb1 tombe : mesure `[À MESURER]` s.

### 4.6 Observabilité (E2)

`node_exporter` sur **toutes** les machines (script `base.sh`),
Prometheus sur obs (cibles engendrées depuis `noeuds.tsv`, intervalle
5 s) + scrape des fronts HAProxy :8404, Grafana provisionné en code
(datasource + tableau de bord « RÉSULTATS-BF » : débit req/s, serveurs
en service, CPU, charge, réseau des répartiteurs, cibles actives).

## 5. Procédures d'exploitation

| Procédure | Commande |
|-----------|----------|
| Reconstruction complète | `vagrant destroy -f && vagrant up` |
| Ajout d'un serveur applicatif | `NB_APP=<N> vagrant up` (reconfig auto du répartiteur) |
| Bascule de base | après panne de bdd1 : `bash scripts/bascule.sh` |
| Retour à la normale | `vagrant destroy -f && vagrant up` (réplique reconstruite proprement) |
| Scénarios de validation | `bash tests/v1…v6_*.sh` depuis la racine |

## 6. Résultats des scénarios

| Scénario | Mesure | Valeur |
|----------|--------|--------|
| V1 répartition | écart max entre serveurs (< 20 %) | `[À MESURER]` |
| V2 panne app1 | requêtes perdues / durée dégradée (< 5 s) | `[À MESURER]` |
| V3 charge N=2 → 4 | req/s ab -n 2000 -c 50 | `[À MESURER]` → `[À MESURER]` |
| V4 panne bdd1 | code 503 puis durée de bascule | `[À MESURER]` s |
| V5 reconstruction | durée totale destroy+up | `[À MESURER]` s |
| V6 panne lb1 | délai de reprise VRRP (< 5 s) | `[À MESURER]` s |

*Commentaire honnête à compléter après mesure : toutes les VM partagent
le processeur de l'hôte ; un débit qui n'augmente pas avec N=4 est un
résultat à expliquer (partage CPU, surcoût psycopg2, saturation du
répartiteur), pas un échec à masquer.*

## 7. Limites connues

- `[À COMPLÉTER après campagne de mesures — ex. : débit plafonné par un
  seul cœur par VM, pas de TLS, VRRP en multicast (unicast à prévoir si
  réseau hôte réticent), graphe Prometheus à 5 s de résolution.]`

## 8. Ce que nous ferions autrement

- `[À COMPLÉTER — ex. : provisionnement Ansible plutôt que shell à
  l'échelle, haproxy via API dyn, tests de charge depuis l'extérieur de
  l'hôte, clôture TLS.]`

# RÉSULTATS-BF — infrastructure résiliente et scalable sous Vagrant

Plateforme de consultation des résultats d'examens par matricule. Toute
l'infrastructure est décrite en code et se reconstruit d'un seul geste :
`vagrant destroy -f && vagrant up`.

## Exigences couvertes

| N°  | Exigence | Où |
|-----|----------|-----|
| R1  | Reconstruction intégrale | `tests/v5_reconstruction.sh` |
| R2  | Idempotence du provisionnement | scripts idempotents (rejouer `vagrant provision` sans effet) |
| R3  | Nombre d'apps paramétrable, config engendrée | `NB_APP=4 vagrant up` + déclencheur de mise à jour du répartiteur |
| R4  | Sonde /sante, éjection < 5 s | HAProxy `inter 2s fall 2` sur `GET /sante` |
| R5  | Réplication en flux bdd1 → bdd2 | `scripts/replique.sh` (basebackup -R) |
| R6  | Bascule chronométrée | `scripts/bascule.sh` + `tests/v4_bascule_bdd.sh` |
| R7  | Aucun secret en clair | `.env` ignoré, `.env.exemple` versionné |
| R8  | Réseau privé, un seul port hôte | port 8080 → lb1 uniquement (VirtualBox) |

Extensions réalisées : **E1** (répartiteur redondant, keepalived/VRRP,
VIP `.10`) et **E2** (Prometheus + Grafana + node_exporter + métriques
HAProxy natives).

## Prérequis

- **Parcours évaluation (imposé)** : poste avec VirtualBox + Vagrant,
  8 Go de RAM libres. Boîte épinglée `bento/ubuntu-24.04` `202502.21.0`.
- **Parcours développement (KVM)** : Ubuntu avec `vagrant-libvirt`
  (`vagrant plugin install vagrant-libvirt`) : le même Vagrantfile et la
  même boîte fonctionnent via libvirt. Aucun port n'est transféré dans ce
  mode : la plateforme s'adresse directement par la VIP sur le réseau privé.

## Démarrage

```bash
git clone <ce-dépot> && cd projet_virtualisation_groupe19
cp .env.exemple .env        # facultatif : engendré automatiquement au 1er up
vagrant up                  # 7 machines : bdd1 bdd2 app1 app2 lb1 lb2 obs
```

Service : `http://192.168.56.10/` (VIP) — ou `http://localhost:8080/`
(VirtualBox uniquement, via lb1).

```bash
curl "http://192.168.56.10/resultat?matricule=100001"
curl http://192.168.56.10/sante
curl http://192.168.56.10/info
```

Grafana : `http://192.168.56.41:3000` (utilisateur `admin`, mot de passe
dans `.env`).

## Paramètres (variables d'environnement)

| Variable | Défaut | Rôle |
|----------|--------|------|
| `NB_APP` | 2 | nombre de serveurs applicatifs — `NB_APP=4 vagrant up` suffit (R3) |
| `GROUPE` | 1 | numéro de groupe → sous-réseau `192.168.{55+G}.0/24` |
| `RESEAU` | selon GROUPE | sous-réseau complet, pour les attributions hors règle 55+G |

> **Point à confirmer avec l'enseignant** : la règle `X = 55 + G` du
> cahier des charges ne couvre que les groupes 1 à 8 (plage autorisée par
> VirtualBox : 192.168.56.0–63.255). Pour un groupe 19, demander le
> sous-réseau attribué puis l'utiliser via `RESEAU=192.168.XX.0 vagrant up`.

## Scénarios de validation (depuis la racine du dépôt)

```bash
bash tests/v1_repartition.sh      # 20 appels /info, écart < 20 %
bash tests/v2_panne_app.sh        # vagrant halt app1 sous charge
bash tests/v3_charge.sh           # ab -n 2000 -c 50 en N=2 puis N=4
bash tests/v4_bascule_bdd.sh      # panne bdd1 + bascule chronométrée
bash tests/v5_reconstruction.sh   # destroy -f puis up, durée mesurée
bash tests/v6_panne_lb.sh         # vagrant halt lb1, bascule VRRP (E1)
```

## Procédure d'exploitation

- **Ajouter un serveur applicatif** : `NB_APP=5 vagrant up` — le
  répartiteur est reconfiguré automatiquement (déclencheur + script
  `rafraichir-haproxy`), sans redémarrage.
- **Bascule de base (R6)** : après `vagrant halt bdd1`, exécuter
  `bash scripts/bascule.sh` — promotion de bdd2, rebasement des
  applications, temps total affiché. Retour à la normale :
  `vagrant destroy -f && vagrant up`.

## Architecture

| Machine | Rôle | Adresse |
|---------|------|---------|
| lb1, lb2 | HAProxy + keepalived (VIP partagée `.10`) | `.11`, `.12` |
| app1…appN | Python/psycopg2, sans état, port 8080 | `.21`…`.2N` |
| bdd1 | PostgreSQL 16 primaire | `.31` |
| bdd2 | Réplique en flux (hot standby) | `.32` |
| obs | Prometheus + Grafana (+ `ab`) | `.41` |

Source unique de vérité : la table `NOEUDS` du `Vagrantfile` engendre
`config/noeuds.tsv`, lu par les scripts du répartiteur et de la
supervision — aucune adresse applicative n'est écrite en dur ailleurs.

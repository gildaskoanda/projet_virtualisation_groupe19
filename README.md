 # RÉSULTATS-BF — infrastructure résiliente et scalable sous Vagrant

Plateforme de consultation des résultats d'examens par matricule. Toute
l'infrastructure est décrite en code et se reconstruit d'un seul geste :
`vagrant destroy -f && vagrant up`.

*Groupe 19 — M1 Informatique, IBAM / UJKZ — réseau du groupe 3 (192.168.58.0/24).*

## Exigences couvertes

| N°  | Exigence | Où |
|-----|----------|-----|
| R1  | Reconstruction intégrale | `tests/v5_reconstruction.sh` |
| R2  | Idempotence du provisionnement | scripts rejouables : `vagrant provision` deux fois de suite ne change rien (fichiers comparés avant écriture, témoin pour la réplique) |
| R3  | Nombre d'apps paramétrable, config engendrée | `NB_APP` + `config/noeuds.tsv` engendré par le Vagrantfile |
| R4  | Sonde /sante, éjection < 5 s | HAProxy : `GET /sante`, `inter 1s fastinter 500ms fall 2`, `timeout check 1s` |
| R5  | Réplication en flux bdd1 → bdd2 | `scripts/replique.sh` (basebackup -R) |
| R6  | Bascule chronométrée | `scripts/bascule.sh` + `tests/v4_bascule_bdd.sh` |
| R7  | Aucun secret en clair | `.env` ignoré par Git, `.env.exemple` versionné (mots de passe BDD, Grafana, VRRP) |
| R8  | Réseau privé, un seul port hôte | port 8080 → lb1 uniquement ; PostgreSQL écoute sur l'IP privée |

Extensions : **E1** (répartiteur redondant, keepalived/VRRP, VIP `.5`) et
**E2** (Prometheus + Grafana + node_exporter + métriques HAProxy natives).

## Prérequis (poste Windows 11 ou Linux)

- **VirtualBox** et **Vagrant**, 8 Go de RAM (le socle seul tient dans 3 Go).
- **Git** (sous Windows : Git Bash). Sous Windows, désactiver Hyper-V /
  « Plateforme de machine virtuelle » si VirtualBox est lent ou refuse de démarrer.
- Boîte épinglée `bento/ubuntu-24.04` version `202502.21.0`, téléchargée au premier `vagrant up`.

## Démarrage

```bash
git clone https://github.com/rootman147/Projet_virtualisation_groupe19.git
cd Projet_virtualisation_groupe19
vagrant up        # le fichier .env est engendré au premier lancement
```

Par défaut, `vagrant up` démarre **7 machines** (socle + extensions, environ
4,4 Go de RAM). Pour travailler avec le socle seul (5 machines, 3 Go) :
mettre `EXTENSIONS=0` dans `.env`. Les extensions se démarrent ensuite à
la demande : `EXTENSIONS=1 vagrant up lb2 obs`.

Service (réseau du groupe 3) :

```bash
curl "http://192.168.58.5/resultat?matricule=100001"   # via la VIP
curl http://192.168.58.5/sante
curl http://192.168.58.5/info
curl http://localhost:8080/info                          # via lb1 seul
```

Grafana : `http://192.168.58.41:3000` (utilisateur `admin`, mot de passe `GRAFANA_MDP` dans `.env`).

## Paramètres (fichier `.env`, ou variable d'environnement qui l'emporte)

| Variable | Défaut | Rôle |
|----------|--------|------|
| `GROUPE` | 3 | de 1 à 8 : sous-réseau `192.168.(55+GROUPE).0/24` (plage VirtualBox 56 à 63) |
| `NB_APP` | 2 | nombre de serveurs applicatifs, de 2 à 9 (R3) |
| `EXTENSIONS` | 1 | 1 = lb2 et obs démarrent aussi ; 0 = socle seul |
| `DB_*`, `GRAFANA_MDP`, `VRRP_PASS` | aléatoires | secrets, jamais versionnés |

> Notre groupe porte le numéro 19, mais la règle du sujet (`X = 55 + G`)
> n'accepte que G de 1 à 8 : nous utilisons le sous-réseau du groupe 3.

## Scénarios de validation (depuis la racine du dépôt)

```bash
bash tests/v1_repartition.sh      # 20 appels /info, écart < 20 %
bash tests/v2_panne_app.sh        # vagrant halt app1 sous consultations continues
bash tests/v3_charge.sh           # ab -n 2000 -c 50 en N=2 puis N=4 (ab sur l'hôte ou sur obs)
bash tests/v4_bascule_bdd.sh      # panne bdd1 + bascule chronométrée
bash tests/v5_reconstruction.sh   # destroy -f puis up, durée mesurée
bash tests/v6_panne_lb.sh         # vagrant halt lb1, bascule VRRP (E1, EXTENSIONS=1)
```

## Procédure d'exploitation

- **Ajouter un serveur applicatif** : `NB_APP=4 vagrant up`. Un déclencheur
  recharge à chaud les répartiteurs déjà démarrés. Si le déclencheur n'a
  pas agi (message d'erreur), la commande de repli est
  `NB_APP=4 vagrant provision lb1 lb2` (idempotente).
- **Bascule de base (R6)** : après `vagrant halt bdd1`, exécuter
  `bash scripts/bascule.sh` : promotion de bdd2, rebasement des
  applications, temps total affiché. Retour à la normale :
  `vagrant destroy -f && vagrant up`.
- **Secrets** : ne jamais ajouter `.env` à Git ; `git ls-files | grep env`
  ne doit afficher que `.env.exemple`.

## Architecture

| Machine | Rôle | Adresse (groupe 3) |
|---------|------|---------|
| lb1, lb2 | HAProxy + keepalived (VIP partagée `.5`) | `.11`, `.12` |
| app1…appN | Python/psycopg2, sans état, port 3000 | `.21`…`.2N` |
| bdd1 | PostgreSQL 16 primaire | `.31` |
| bdd2 | Réplique en flux (hot standby) | `.32` |
| obs | Prometheus + Grafana (+ `ab`) | `.41` |

Source unique de vérité : la table `NOEUDS` du `Vagrantfile` engendre
`config/noeuds.tsv`, lu par les scripts du répartiteur et de la
supervision. Aucune adresse applicative n'est écrite en dur ailleurs.

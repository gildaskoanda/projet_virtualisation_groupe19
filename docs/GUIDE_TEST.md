# Guide de test complet : RÉSULTATS-BF

*Groupe 19, M1 Informatique, IBAM / UJKZ. Réseau du groupe 3 (192.168.58.0/24).*

Ce guide part de zéro : il explique comment récupérer le projet sur GitHub, le démarrer, puis tester **toutes** les exigences (R1 à R8), les scénarios (V1 à V6) et les extensions (E1 et E2). Chaque étape donne la commande exacte et le résultat attendu.

## Règles à suivre pendant tout le guide

- Toutes les commandes se tapent dans **Git Bash** (Windows), depuis la **racine du dépôt** (le dossier qui contient le `Vagrantfile`).
- Faites les étapes **dans l'ordre**. Arrêtez-vous à la première qui échoue et consultez la section « Dépannage ».
- **Ne collez jamais un mot de passe** (contenu de `.env`) dans un message, un document ou un commit.
- Si une machine échoue à se provisionner, relancez `vagrant provision <machine>`. **Ne relancez pas `vagrant up` seul** : il ne reprovisionne pas une machine déjà allumée.
- Les durées marquées *(mesuré)* viennent de nos essais ; celles marquées *(estimation)* sont à vérifier chez vous.

## Plan et durées

| Partie | Contenu | Durée |
|---|---|---|
| 1 | Installer les outils | 20 à 40 min (téléchargements) |
| 2 | Récupérer le projet | 2 min |
| 3 | Configurer | 2 min |
| 4 | Démarrer le socle (5 VM) | environ 37 min *(mesuré, connexion lente)* |
| 5 | Vérifications fonctionnelles, R5, R7, R8 | 10 min |
| 6 | Idempotence (R2) | 10 min *(estimation)* |
| 7 | Scénarios V1 et V2 | 10 min *(estimation)* |
| 8 | Extensions E1 et E2, scénarios V6 et V3 | 30 à 50 min *(estimation)* |
| 9 | Scénarios V4 puis V5 (destructifs) | V4 : quelques minutes ; V5 : environ 37 min *(mesuré)* |
| 10 | Enregistrer les mesures dans Git | 5 min |

**Ressources** : un PC avec 8 Go de RAM, environ 20 Go d'espace disque libre *(précaution)*, une connexion Internet. Le socle (5 VM) utilise environ 3 Go de RAM ; avec les extensions (7 VM), environ 4,4 Go ; avec 4 serveurs applicatifs, environ 5,4 Go. Fermez les autres programmes lourds.

---

## Partie 1 : installer les outils (une seule fois)

### 1.1 Git pour Windows

1. Téléchargez l'installateur sur `https://git-scm.com/download/win` et installez-le avec les options par défaut, sauf :
   - **Default branch name** : *Override*, tapez `main`.
   - **Line ending conversions** : *Checkout as-is, commit as-is*.
2. Ouvrez **Git Bash** (menu Démarrer) et configurez votre identité :

```bash
git --version
git config --global user.name "Votre Nom"
git config --global user.email "votre-email@exemple.com"
```

### 1.2 VirtualBox et Vagrant

1. Installez **VirtualBox** (`https://www.virtualbox.org`, *Windows hosts*), puis **Vagrant** (`https://developer.hashicorp.com/vagrant`, Windows 64-bit). Redémarrez le PC.
2. Si Hyper-V ou la « Plateforme de machine virtuelle » est activé dans Windows, VirtualBox peut être très lent ou refuser de démarrer : désactivez-les si c'est le cas.
3. Vérifiez dans Git Bash :

```bash
vagrant --version
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" --version
```

Attendu : un numéro de version pour chacun. Si Git Bash répond `VBoxManage: command not found` avec le nom court, ce n'est pas bloquant. Pour l'ajouter une fois pour toutes :

```bash
echo 'export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"' >> ~/.bashrc
source ~/.bashrc
```

### 1.3 Un éditeur de texte (facultatif)

**Visual Studio Code** (`https://code.visualstudio.com`). Dans les paramètres, réglez `files.eol` sur `\n` (LF) pour que les scripts ne soient pas enregistrés en CRLF.

---

## Partie 2 : récupérer le projet depuis GitHub

Le dépôt est privé : votre compte GitHub doit avoir été invité comme collaborateur. Lors du premier `clone`, une fenêtre de navigateur demande de vous connecter.

```bash
cd ~/Documents
git clone https://github.com/rootman147/Projet_virtualisation_groupe19.git
cd Projet_virtualisation_groupe19
git checkout main
git pull --no-edit
git config core.autocrlf false
```

Vérifications :

```bash
ls
ls scripts tests sql app config
git ls-files | grep -i "^\.env"
grep -c "V6_FORCE" tests/v6_panne_lb.sh
```

Attendu :

- `ls` montre au moins `Vagrantfile`, `README.md`, `scripts`, `tests`, `docs`, `app`, `sql`, `config`.
- `scripts` contient `app.sh base.sh bascule.sh bdd.sh lb.sh obs.sh replique.sh` et le dossier `lib` ; `tests` contient `_lib.sh` et `v1` à `v6`.
- `git ls-files | grep -i "^\.env"` affiche **uniquement** `.env.exemple`.
- Le dernier `grep -c` affiche `2` (ou plus) : vous avez les scripts de test corrigés. Si c'est `0`, la fusion des correctifs dans `main` n'est pas faite : `git fetch --all`, puis `git checkout fix/corrections-revue` et `git pull`.

---

## Partie 3 : configurer

Le fichier `.env` contient les mots de passe et les paramètres. Il **n'est jamais versionné** : il est engendré automatiquement au premier appel de Vagrant, avec des mots de passe aléatoires (c'est ce qui permet la reconstruction sans geste manuel, R1).

```bash
vagrant validate
grep -E "^(GROUPE|NB_APP|EXTENSIONS)=" .env
```

Attendu :

- `vagrant validate` affiche d'abord un message disant que `.env` a été engendré, puis `Vagrantfile validated successfully.`
- Le `grep` affiche `GROUPE=3`, `NB_APP=2` et `EXTENSIONS=1`.

Pour la première phase, on démarre le **socle seul** (5 machines) :

```bash
sed -i 's/^EXTENSIONS=.*/EXTENSIONS=0/' .env
grep "^EXTENSIONS=" .env
```

Attendu : `EXTENSIONS=0`.

---

## Partie 4 : démarrer le socle

```bash
vagrant up 2>&1 | tee ~/vagrant-up.log
```

- La **première fois**, Vagrant télécharge la boîte `bento/ubuntu-24.04` (version `202502.21.0`) : cela peut être long. Ne fermez pas la fenêtre.
- Vous devez voir défiler des lignes `==> bdd1: Running provisioner: ...`. **Si rien de tel n'apparaît**, vous êtes sur une mauvaise version du Vagrantfile (voir Dépannage).
- Les messages `Warning: Connection reset. Retrying...` au démarrage d'une machine sont normaux.

Vérifiez l'état :

```bash
vagrant status
for m in bdd1 bdd2 app1 app2 lb1; do echo "== $m"; vagrant ssh $m -c "systemctl is-active postgresql haproxy resultats 2>/dev/null | tr '\n' ' '"; echo; done
```

Attendu : 5 machines `running`, et pour chaque machine l'état `active` du service correspondant.

| Machine | Service qui doit être `active` |
|---|---|
| bdd1, bdd2 | `postgresql` (première position) |
| app1, app2 | `resultats` (troisième position) |
| lb1 | `haproxy` (deuxième position) |

---

## Partie 5 : vérifications fonctionnelles

### 5.1 La base de données et la réplication (R5)

```bash
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -tAc 'SELECT count(*) FROM resultats'"
vagrant ssh bdd1 -c "sudo -u postgres psql -tAc 'SELECT client_addr, state FROM pg_stat_replication'"
vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'"
```

Attendu : `50000`, puis `192.168.58.32|streaming`, puis `t` (bdd2 est une réplique en lecture seule).

**Preuve R5** : une écriture sur bdd1 est visible sur bdd2.

```bash
mkdir -p docs/mesures
{
  vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -c \"INSERT INTO resultats VALUES (999999,'Test R5','D',12.5,true)\""
  vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats -tAc 'SELECT * FROM resultats WHERE matricule=999999'"
  vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -c 'DELETE FROM resultats WHERE matricule=999999'"
} 2>&1 | tee docs/mesures/r5.txt
```

Attendu : la ligne `999999|Test R5|D|12.50|t` s'affiche depuis bdd2 ; la dernière commande supprime la ligne de test.

### 5.2 Les serveurs applicatifs

```bash
vagrant ssh app1 -c "curl -s localhost:3000/sante; echo; curl -s localhost:3000/info; echo"
vagrant ssh app2 -c "curl -s localhost:3000/sante; echo; curl -s localhost:3000/info; echo"
```

Attendu, pour chacun : `{"statut":"ok","base":"accessible"}` puis `{"hote":"app1"}` (ou `app2`).

### 5.3 Le répartiteur et l'adresse virtuelle

```bash
vagrant ssh lb1 -c "grep server /etc/haproxy/haproxy.cfg"
vagrant ssh lb1 -c "ip -4 addr show | grep 192.168.58.5"
```

Attendu : deux lignes `server app1 192.168.58.21:3000 check` et `server app2 192.168.58.22:3000 check`, puis la VIP `192.168.58.5/24` portée par lb1.

### 5.4 Le service vu depuis votre PC

```bash
curl http://192.168.58.5/sante
curl http://192.168.58.5/info
curl "http://192.168.58.5/resultat?matricule=100001"
curl -i http://localhost:8080/info
```

Attendu : du JSON avec un code 200 à chaque fois. Le matricule 100001 doit afficher `"nom":"Candidat 00001"`. Si `192.168.58.5` ne répond pas mais que `localhost:8080` répond, voir Dépannage (réseau hôte).

### 5.5 Cloisonnement réseau (R8)

```bash
grep -n forwarded_port Vagrantfile
vagrant port lb1
vagrant port bdd1
vagrant ssh bdd1 -c "sudo ss -ltn | grep 5432"
```

Attendu :

- Le `Vagrantfile` ne contient **qu'une seule** redirection de port, pour `lb1` (8080 vers 80).
- `vagrant port lb1` montre le port 80 redirigé vers 8080 de votre PC ; `vagrant port bdd1` ne montre que SSH (le canal de gestion de Vagrant) : aucun port de la base n'est exposé vers l'hôte.
- PostgreSQL écoute sur `192.168.58.31:5432` (l'adresse privée) et non sur `0.0.0.0`.

### 5.6 Aucun secret dans le dépôt (R7)

```bash
git ls-files | grep -i "^\.env"
git log --all --oneline -- .env
git grep -n -iE "(password|mdp|pass)=[A-Za-z0-9]{6,}" -- . ":!.env.exemple" ":!docs"
```

Attendu : la première commande affiche **uniquement** `.env.exemple` ; les deux autres n'affichent **rien**.

Vérification de l'historique pour l'ancien mot de passe VRRP écrit en clair par le passé :

```bash
git log --all -p -S"rbf2026" --oneline -- scripts/lb.sh | head -20
```

Si cette commande affiche des lignes, l'ancien mot de passe est encore visible dans l'historique (voir la section « Décision à prendre en équipe » du bilan : purge ou documentation dans le dossier).

---

## Partie 6 : idempotence (R2)

Le sujet demande que `vagrant provision` rejoué deux fois de suite ne modifie rien et n'échoue pas. On compare des empreintes de fichiers avant et après, ainsi que l'heure de démarrage de PostgreSQL (qui prouve qu'il n'a pas été redémarré).

**Avant :**

```bash
{
  echo "=== AVANT"
  vagrant ssh lb1  -c "sudo md5sum /etc/haproxy/haproxy.cfg /etc/keepalived/keepalived.conf"
  vagrant ssh bdd1 -c "sudo md5sum /etc/postgresql/16/main/conf.d/resultats.conf /etc/postgresql/16/main/pg_hba.conf"
  vagrant ssh bdd2 -c "sudo md5sum /etc/postgresql/16/main/conf.d/resultats.conf /etc/postgresql/16/main/pg_hba.conf"
  vagrant ssh bdd1 -c "sudo -u postgres psql -tAc 'SELECT pg_postmaster_start_time()'"
  vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_postmaster_start_time()'"
} 2>&1 | tee docs/mesures/r2_avant.txt
```

**Deux provisionnements consécutifs** (plusieurs minutes) :

```bash
vagrant provision lb1 app1 bdd1 bdd2 2>&1 | tee docs/mesures/r2_provision1.txt | grep -iE "inchangee|ignoré|OK|error|erreur|failed"
vagrant provision lb1 app1 bdd1 bdd2 2>&1 | tee docs/mesures/r2_provision2.txt | grep -iE "inchangee|ignoré|OK|error|erreur|failed"
```

**Après, et comparaison :**

```bash
{
  echo "=== APRES"
  vagrant ssh lb1  -c "sudo md5sum /etc/haproxy/haproxy.cfg /etc/keepalived/keepalived.conf"
  vagrant ssh bdd1 -c "sudo md5sum /etc/postgresql/16/main/conf.d/resultats.conf /etc/postgresql/16/main/pg_hba.conf"
  vagrant ssh bdd2 -c "sudo md5sum /etc/postgresql/16/main/conf.d/resultats.conf /etc/postgresql/16/main/pg_hba.conf"
  vagrant ssh bdd1 -c "sudo -u postgres psql -tAc 'SELECT pg_postmaster_start_time()'"
  vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_postmaster_start_time()'"
  echo "--- blocs resultats-bf dans pg_hba (attendu : 1 et 1)"
  vagrant ssh bdd1 -c "sudo grep -c '# resultats-bf' /etc/postgresql/16/main/pg_hba.conf"
  vagrant ssh bdd2 -c "sudo grep -c '# resultats-bf' /etc/postgresql/16/main/pg_hba.conf"
  echo "--- lignes dans la table (attendu : 50000)"
  vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -tAc 'SELECT count(*) FROM resultats'"
} 2>&1 | tee docs/mesures/r2_apres.txt
diff <(sed -n '/AVANT/,$p' docs/mesures/r2_avant.txt | tail -n +2) <(sed -n '/APRES/,$p' docs/mesures/r2_apres.txt | tail -n +2 | head -n 8) && echo "IDEMPOTENCE : OK, rien n'a change"
```

Attendu :

- Aucune erreur dans les deux provisionnements ; messages `configuration inchangee` et `basebackup ignoré (idempotence)`.
- Le `diff` ne trouve **aucune différence** (empreintes et heures de démarrage identiques) et affiche `IDEMPOTENCE : OK`.
- Les deux blocs `pg_hba` valent `1` ; la table contient `50000` lignes.

Limite à signaler dans le dossier : le provisionnement des applications redémarre leur service à chaque fois (sans effet sur les données : l'application est sans état).

---

## Partie 7 : scénarios V1 et V2

### V1 : répartition (20 appels à `/info`)

```bash
bash tests/v1_repartition.sh | tee docs/mesures/v1.txt
```

Attendu : les deux serveurs apparaissent en alternance (`app1` et `app2` 10 fois chacun), `Serveurs vus : 2 / 2`, un écart de 0 % (exigence : moins de 20 %) et `RÉSULTAT V1 : OK`.

### V2 : panne d'un serveur applicatif sous charge

```bash
bash tests/v2_panne_app.sh | tee docs/mesures/v2.txt
vagrant status
```

Durée : 3 à 4 minutes *(estimation)* : le redémarrage de `app1` est long. Attendu :

- `app1 vue pendant la panne : 0 fois sur 12` (la preuve que HAProxy l'a éjectée) ;
- `app1 réintégrée : oui, après N s` ;
- le nombre de réponses en erreur, la période dégradée (moins de 5 s exigées) et la latence maximale ;
- un verdict `OK` ou `ACCEPTABLE`.

Si `app1` reste arrêtée ensuite : `vagrant up app1`.

**Pire cas** (coupure brutale, sans refus de connexion propre) :

```bash
V2_FORCE=1 bash tests/v2_panne_app.sh | tee docs/mesures/v2_force.txt
```

---

## Partie 8 : les extensions (E1 et E2), puis V6 et V3

### 8.1 Allumer lb2 et obs

```bash
sed -i 's/^EXTENSIONS=.*/EXTENSIONS=1/' .env
vagrant up lb2 obs 2>&1 | tee ~/vagrant-ext.log | tail -30
vagrant status
```

La machine `obs` installe Prometheus et Grafana : 10 à 20 minutes *(estimation)*. Attendu : 7 machines `running`. En cas d'échec d'un téléchargement : `vagrant provision obs` (ou `lb2`).

### 8.2 Vérifier E1 (répartiteur redondant)

```bash
vagrant ssh lb2 -c "systemctl is-active haproxy keepalived | tr '\n' ' '"
vagrant ssh lb1 -c "ip -4 addr show | grep -c 192.168.58.5"
vagrant ssh lb2 -c "ip -4 addr show | grep -c 192.168.58.5"
vagrant ssh lb2 -c "grep server /etc/haproxy/haproxy.cfg"
```

Attendu : `active active`, puis `1` (la VIP est sur lb1), puis `0` (pas sur lb2), puis les deux lignes `server app1` et `server app2`.

### 8.3 V6 : panne du répartiteur

```bash
bash tests/v6_panne_lb.sh | tee docs/mesures/v6.txt
vagrant status
```

Attendu :

- Soit `Interruption visible : aucune`, soit une durée **inférieure à 5 s** ;
- `VIP portée par lb2 : 1 (attendu : 1)` ;
- `RÉSULTAT V6 : OK`.

Pendant ce test, `localhost:8080` ne répond plus : c'est normal (ce port n'existe que sur lb1). Seule la VIP `192.168.58.5` compte. Le script remet `lb1` en marche à la fin.

**Pire cas** (coupure brutale : lb1 n'annonce pas son départ, lb2 doit le déduire seul) :

```bash
V6_FORCE=1 bash tests/v6_panne_lb.sh | tee docs/mesures/v6_force.txt
```

### 8.4 Vérifier E2 (supervision)

```bash
curl -s http://192.168.58.41:9090/-/healthy
grep GRAFANA_MDP .env
```

La seconde commande affiche votre mot de passe Grafana **dans votre terminal uniquement** : ne le copiez nulle part. Dans le navigateur :

- `http://192.168.58.41:9090/targets` : toutes les cibles doivent être `UP`.
- `http://192.168.58.41:3000` : utilisateur `admin`, mot de passe `GRAFANA_MDP`. Le tableau de bord RÉSULTATS-BF doit être chargé.

Si le panneau du débit affiche « No data », relevez le nom exact de la métrique :

```bash
curl -s http://192.168.58.11:8404/metrics | grep -E "^haproxy_frontend_(http_)?requests" | head -5
```

### 8.5 V3 : montée en charge

Gardez **Grafana ouvert** pendant le test et faites des **captures d'écran** du débit qui monte (exigées par E2). Fermez les autres programmes : la plateforme passera à 9 machines (environ 5,4 Go).

```bash
bash tests/v3_charge.sh | tee docs/mesures/v3.txt
```

Le script mesure le débit avec 2 serveurs (`ab -n 2000 -c 50`), ajoute `app3` et `app4`, attend que le répartiteur les voie, puis mesure à nouveau. Les sorties complètes d'`ab` sont conservées dans `docs/mesures/v3_ab_N2.txt` et `docs/mesures/v3_ab_N4.txt`.

**Preuve R3** (le nombre de serveurs est un paramètre) : tant que 4 serveurs tournent,

```bash
vagrant ssh lb1 -c "grep -c 'server app' /etc/haproxy/haproxy.cfg"
```

Attendu : `4`. La configuration du répartiteur a suivi toute seule.

**Interprétation honnête** : les VM partagent le processeur de votre PC. Doubler les serveurs ne doublera pas le débit, et il peut baisser. Ce n'est pas un échec : rapportez vos chiffres tels quels et expliquez-les dans le dossier.

**Retour à 2 serveurs** :

```bash
NB_APP=4 vagrant destroy -f app3 app4
vagrant provision lb1 lb2
vagrant ssh lb1 -c "grep -c 'server app' /etc/haproxy/haproxy.cfg"
```

Attendu : `2`. Sans `NB_APP=4`, Vagrant ne connaît pas `app3` ni `app4`, et la première commande échouerait.

---

## Partie 9 : les scénarios destructifs

### 9.1 V4 : panne de la base primaire et bascule

**À faire en dernier ou presque : après ce test, bdd2 est la primaire et bdd1 est arrêtée.** Ne faites **jamais** `vagrant up bdd1` ensuite : elle redémarrerait comme ancienne primaire avec des données divergentes. Le retour à la normale passe par V5.

Vérifiez d'abord l'état de départ :

```bash
vagrant status
curl http://192.168.58.5/sante
vagrant ssh bdd1 -c "sudo -u postgres psql -tAc 'SELECT client_addr, state FROM pg_stat_replication'"
```

Attendu : machines `running`, un 200, et `192.168.58.32|streaming`. Puis :

```bash
bash tests/v4_bascule_bdd.sh | tee docs/mesures/v4.txt
```

Attendu :

- Avant la panne : `/sante -> 200`.
- Après `vagrant halt bdd1` : `/sante -> 503` (un 503 propre, jamais une page blanche).
- La procédure de bascule affiche `bdd2 est désormais primaire`, puis `app1 rebasculé` et `app2 rebasculé`.
- `Bascule terminée en N secondes — /sante renvoie 200` (mesuré chez nous : 74 s) et `RÉSULTAT V4 : OK`.

**Preuve complémentaire** (bdd2 accepte les écritures et les applications lisent dessus) :

```bash
{
  vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'"
  vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats -tAc \"INSERT INTO resultats VALUES (888888,'Test bascule','D',11,true) RETURNING matricule\""
  curl "http://192.168.58.5/resultat?matricule=888888"
} 2>&1 | tee docs/mesures/v4_apres.txt
```

Attendu : `f`, `888888`, puis le JSON du candidat « Test bascule ».

### 9.2 V5 : reconstruction complète (R1)

Cette étape **détruit toutes les machines** puis relance `vagrant up` en mesurant la durée. Elle ramène aussi la plateforme à l'état normal après V4.

Choisissez la configuration à reconstruire : `EXTENSIONS=0` pour mesurer le socle, `EXTENSIONS=1` pour reconstruire aussi lb2 et obs.

```bash
bash tests/v5_reconstruction.sh | tee docs/mesures/v5.txt
```

Durée : environ 37 minutes pour le socle *(mesuré, connexion lente)*. Attendu :

- `Durée totale de reconstruction : N s` ;
- `Sonde de santé après reconstruction : /sante -> 200` ;
- `RÉSULTAT V5 : OK`.

Aucune commande ne doit être tapée à la main pendant la reconstruction : c'est la preuve de R1. Une fois terminée, refaites la section 5.4 (les `curl`) pour confirmer que tout répond à nouveau.

---

## Partie 10 : enregistrer les mesures dans Git

Les fichiers de `docs/mesures/` sont les **preuves** des résultats du dossier (commande, résultat brut). Ils ne contiennent aucun mot de passe.

```bash
git status
git ls-files | grep -i "^\.env"
git add docs/mesures
git commit -m "docs(mesures): resultats des scenarios de validation"
git push
```

La deuxième commande doit afficher **uniquement** `.env.exemple`. Ne faites jamais `git add .env` ni `git add -A` sans avoir lu `git status`.

---

## Dépannage

| Symptôme | Cause probable | Que faire |
|---|---|---|
| `vagrant up` ou `vagrant provision` n'affiche **rien** (pas de `Running provisioner`) | Mauvaise version du Vagrantfile (ancienne branche) | `git branch`, `git checkout main`, `git pull` ; vérifiez que `ls scripts` montre tous les scripts |
| `could not be found ... no available version that matches` pour la boîte | Version de la boîte indisponible | Voir `VERSION_BOITE` dans le `Vagrantfile` ; versions disponibles : `202510.26.0`, `202508.03.0`, `202502.21.0`, `202404.26.0` ; elle doit être **identique chez les 4 membres** |
| `sudo: unknown user postgres` sur bdd1 | bdd1 jamais provisionnée | `vagrant provision bdd1`, puis `bdd2`, `app1 app2`, `lb1`, dans cet ordre |
| `Permission denied` en lisant `pg_hba.conf` | Le fichier n'est lisible qu'en administrateur | Ajoutez `sudo` devant la commande |
| `/sante` des apps répond 503 | L'app n'atteint pas la base | `vagrant ssh app1 -c "sudo journalctl -u resultats -n 20 --no-pager"` : cherchez `no pg_hba.conf entry` ou `password authentication failed` |
| `pg_stat_replication` est vide | bdd2 non connectée | `vagrant ssh bdd2 -c "sudo tail -20 /var/log/postgresql/postgresql-16-main.log"` |
| `curl` sur la VIP renvoie 503 | HAProxy voit les apps mortes | `vagrant ssh lb1 -c "grep server /etc/haproxy/haproxy.cfg"` et `vagrant ssh lb1 -c "sudo journalctl -u haproxy -n 20 --no-pager"` |
| La VIP `192.168.58.5` ne répond pas depuis le PC, mais `localhost:8080` oui | Réseau hôte VirtualBox ou pare-feu Windows | Testez `ping 192.168.58.1` ; vérifiez la carte « VirtualBox Host-Only » et le pare-feu ; en dernier recours, démarrez avec `localhost:8080` |
| La VIP n'est portée par aucun répartiteur | keepalived en échec | `vagrant ssh lb1 -c "sudo systemctl status keepalived --no-pager \| head -15"` |
| `vagrant up` reste bloqué sur « Waiting for machine to boot » | Virtualisation absente ou conflit Hyper-V | Activez la virtualisation dans le BIOS ; désactivez Hyper-V ; patientez quelques minutes |
| Mémoire insuffisante (PC lent, VM qui s'arrêtent) | Trop de machines | `EXTENSIONS=0` dans `.env`, fermez les autres programmes, retirez `app3` et `app4` |
| `port 8080 ... collision` | Un autre programme utilise 8080 | Fermez-le ou redémarrez ; Vagrant corrige parfois seul le port SSH, pas celui de 8080 |
| `bash: tests/vX.sh: No such file` | Vous n'êtes pas à la racine du dépôt | `cd ~/Documents/Projet_virtualisation_groupe19` |
| Scripts en CRLF (`\r: command not found`) | Fichiers enregistrés avec des fins de ligne Windows | `git config core.autocrlf false`, `git add --renormalize .` ; VS Code : `files.eol` à `\n` |
| Après V4 : `vagrant up bdd1` démarre une base qui diverge | L'ancienne primaire redémarre en primaire | Ne le faites pas ; reconstruisez avec V5 |

---

## Récapitulatif à remplir

Reportez ici vos résultats réels (copiés depuis `docs/mesures/`), pour le dossier. **Ne notez que des valeurs mesurées.**

| Exigence ou scénario | Commande ou preuve | Résultat attendu | Votre résultat | Fait |
|---|---|---|---|---|
| R1 reconstruction | `bash tests/v5_reconstruction.sh` | Plateforme fonctionnelle sans geste manuel | durée : ______ s | [ ] |
| R2 idempotence | partie 6 | Aucune différence avant/après | | [ ] |
| R3 N paramétrable | `NB_APP=4` (V3) + `grep -c 'server app'` | 4 serveurs sans toucher au répartiteur | | [ ] |
| R4 sonde de santé | V2 | App éjectée en moins de 5 s | période dégradée : ______ s | [ ] |
| R5 réplication | partie 5.1 | Ligne insérée sur bdd1 visible sur bdd2 | | [ ] |
| R6 bascule | V4 | Procédure exécutable et chronométrée | durée : ______ s | [ ] |
| R7 aucun secret | partie 5.6 | Seul `.env.exemple` versionné | | [ ] |
| R8 réseau privé | partie 5.5 | Un seul port exposé (lb1) | | [ ] |
| V1 répartition | `tests/v1_repartition.sh` | Écart inférieur à 20 % | écart : ______ % | [ ] |
| V2 panne d'une app | `tests/v2_panne_app.sh` | Service disponible, dégradation inférieure à 5 s | erreurs : ______ ; latence max : ______ s | [ ] |
| V3 montée en charge | `tests/v3_charge.sh` | Débit mesuré pour N=2 et N=4 | N=2 : ______ req/s ; N=4 : ______ req/s | [ ] |
| V4 panne de la base | `tests/v4_bascule_bdd.sh` | 503 propre, puis bascule | durée de bascule : ______ s | [ ] |
| V5 reconstruction | `tests/v5_reconstruction.sh` | `/sante` à 200 | durée : ______ s | [ ] |
| V6 panne du répartiteur (E1) | `tests/v6_panne_lb.sh` | VIP joignable, interruption inférieure à 5 s | interruption : ______ s | [ ] |
| E2 supervision | Grafana (partie 8.4) | Débit visible pendant la charge, serveur qui disparaît pendant la panne | captures : ______ | [ ] |

## Fin de session

```bash
vagrant halt            # éteint les machines, conserve leur contenu
vagrant destroy -f      # supprime toutes les machines (ne touche ni au code ni au .env)
```

Pour reprendre ensuite : `vagrant up` (après `halt`) ou `bash tests/v5_reconstruction.sh` (après `destroy`).

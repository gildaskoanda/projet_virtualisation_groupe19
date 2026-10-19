# Journal de bord — RÉSULTATS-BF (groupe 19)

## Répartition des rôles

| Membre | Rôle (cahier des charges) |
|--------|---------------------------|
| VyDonald | assemblage général : Vagrantfile, provisionnement, répartiteur, bascule, scénarios |
| `[membre 2]` | ingénieur applicatif |
| `[membre 3]` | ingénieur données |
| `[membre 4]` | ingénieur essais et observabilité |

*La rotation (au moins un commit par membre hors de son domaine) sera
tracée par l'historique Git.*

## Décisions prises et pourquoi

1. **Une seule table `NOEUDS` dans le Vagrantfile**, engendrant
   `config/noeuds.tsv` lu par HAProxy, Prometheus et les scripts
   d'exploitation. C'est la seule façon de satisfaire R3 sans adresse en
   dur (pénalité −2).
2. **Boîte `bento/ubuntu-24.04` épinglée en `202502.21.0`** : version
   publiée à la fois pour virtualbox (environnement d'évaluation) et
   libvirt (poste de développement sous KVM) — un seul dépôt, deux
   hyperviseurs, aucune divergence.
3. **Dossier synchronisé désactivé**, fichiers déposés par provisionneurs
   `file` : le provisionnement ne dépend d'aucune technologie de
   partage (vboxsf/9p), fragile sous libvirt.
4. **Connexion PostgreSQL ouverte à la demande** dans l'app (pas de pool)
   : un serveur démarre même si la base est absente (piège n°4), et son
   retrait reste indolore.
5. **`.env` engendré automatiquement au premier `vagrant up`** avec mots
   de passe aléatoires : R1 (zéro geste manuel) compatible avec R7
   (aucun secret dans l'historique).
6. **Extensions E1 + E2 retenues** : E1 supprime le point de défaillance
   unique du répartiteur ; E2 fournit les preuves visuelles exigées par
   les scénarios (débit en charge, serveur disparaissant en panne).

## Difficultés rencontrées et levées

| Difficulté | Solution |
|------------|----------|
| Poste Windows de développement sans droits admin : VirtualBox/Wagrant impossibles | bascule du développement sur un poste Ubuntu 24.04 avec KVM ; le dépôt reste conforme VirtualBox pour la démonstration |
| Règle de sous-réseau du PDF (`X=55+G`) incompatible avec un numéro de groupe 19 (plage 56–63 saturée) | variable `RESEAU` surchargeable — à régler avec l'enseignant avant la démonstration |
| Mise à jour du répartiteur quand `NB_APP` change sans reprovisionner lb | déclencheur Vagrant `after :up` + script `rafraichir-haproxy` (`reload` à chaud) |
| `[à compléter au fil des tests]` | |

## Chronologie

- **J1** — Écriture du dépôt complet : Vagrantfile (source unique de
  vérité), provisionnement des 7 machines, application sans état,
  réplication, répartiteur engendré, extensions E1/E2, scénarios V1–V6,
  README, dossier et journal (squelettes). Pull request `davy` ouverte.
- **J2** — `[à compléter : premier vagrant up sous KVM, bugs corrigés]`
- **J3** — `[à compléter : campagne V1–V6, relevés]`
- **J4** — `[à compléter : dossier complété, répétition de démonstration]`

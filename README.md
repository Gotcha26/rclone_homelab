# Rclone Homelab Manager

### _Le script de synchronisation pour votre homelab Proxmox_
_✌️🥖🔆 Fait avec amour dans le sud de la France. ❤️🇫🇷🐓_

---

Vous avez un serveur Proxmox, des conteneurs LXC, des fichiers importants un peu partout... et aucune envie de tout perdre le jour où un disque lâche ?

**Rclone Homelab Manager** rend la sauvegarde de votre homelab simple, automatisée et fiable. Un menu interactif vous guide, le mode automatique fait le reste. Aucune connaissance préalable requise.

---

## Rclone, c'est quoi ?

[Rclone](https://rclone.org/) est un outil open source en ligne de commandes — souvent décrit comme le **"couteau suisse" du transfert de fichiers**. Il sait copier et synchroniser vos données entre votre machine et plus de **70 fournisseurs cloud** : Google Drive, OneDrive, Dropbox, Amazon S3, tout serveur SFTP/FTP, un NAS, un autre PC...

C'est un outil extrêmement puissant, mais sa richesse en fait aussi un outil complexe à maîtriser : des dizaines d'options, une syntaxe à connaître, pas d'interface graphique.

**Rclone Homelab Manager prend le relais** : il enveloppe rclone dans un script intelligent qui s'occupe de tout orchestrer pour vous — vous n'avez qu'à dire *quoi* synchroniser et *vers où*.

---

## La règle de sauvegarde 3-2-1

La convention **3-2-1** est la référence en matière de protection des données :
- **3** copies de vos données
- sur **2** supports différents
- dont **1** copie hors site (un autre lieu physique)

Rclone Homelab Manager rend cette règle triviale à appliquer. Un exemple concret :

> Votre installation **Home Assistant** sur Proxmox génère déjà ses propres sauvegardes sur le NAS local — c'est bien, mais si un incendie, une surtension ou un cambriolage touche votre domicile, tout est perdu.
>
> Avec Rclone Homelab Manager, vous ajoutez quelques lignes de jobs et ces sauvegardes sont automatiquement synchronisées vers un cloud (OneDrive, Google Drive...), chez un voisin de confiance via SFTP, ou sur un second NAS dans une autre pièce.
>
> **Résultat** : vos données existent en 3 exemplaires, sur 2 supports différents, dont 1 hors site. La règle 3-2-1 est respectée, sans effort.

---

## Pourquoi Rclone Homelab Manager ?

**Parce que vos données méritent mieux qu'un "je ferai une sauvegarde demain".**

- **Un menu interactif** qui vous prend par la main : pas besoin d'être expert, le script vous guide à chaque étape
- **Multi-jobs** : synchronisez plusieurs dossiers vers plusieurs destinations en une seule commande
- **100% automatisable** : programmez vos sauvegardes via cron et oubliez-les (un assistant intégré vous aide à créer la tâche)
- **Compatible avec tous vos clouds** : OneDrive, Google Drive, Dropbox, SFTP, S3... tout ce que rclone supporte
- **Pensé pour Proxmox / LXC** : conçu spécifiquement pour les environnements homelab sous Debian
- **Règle 3-2-1 en un clin d'oeil** : multipliez les destinations de sauvegarde sans complexité

## Ce qui change votre quotidien

| Avant | Avec Rclone Homelab Manager |
|-------|----------------------------|
| Des commandes rclone à retaper à chaque fois | Un fichier de jobs simple : 1 ligne = 1 sauvegarde |
| Aucune idée si la sauvegarde a marché | Rapports par email et/ou notifications Discord |
| Pas de sauvegarde automatique | Mode `--auto` + cron = tranquillité d'esprit |
| Configuration éparpillée | Fichiers locaux préservés à chaque mise à jour |
| Mise à jour manuelle | Système de mise à jour intégré avec détection automatique |

## Fonctionnalités

- Menu interactif complet pour tout configurer sans quitter le terminal
- Mode simulation (`--dry-run`) pour vérifier avant d'agir
- Rapports HTML par email via msmtp
- Notifications Discord par webhook
- Détection automatique des problèmes d'accès (dossiers, remotes, tokens expirés)
- Configuration locale persistante (jamais écrasée par les mises à jour)
- Résumé clair après chaque exécution
- Coloration syntaxique à l'écran et dans les mails
- Planification cron assistée par un wizard interactif
- Accepte toutes les options natives de rclone en passthrough
- ❗ Vous rend riche, beau et irrésistible

## Installation rapide

```bash
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh)
```

C'est tout. Le script s'occupe du reste.

## Premier lancement

```bash
rclone_homelab
```

Le menu interactif s'ouvre et vous guide pour :
1. Configurer rclone (si pas déjà fait)
2. Créer votre fichier de jobs (quoi synchroniser, vers où)
3. Lancer vos premières sauvegardes
4. Programmer une tâche automatique via cron

## Documentation

Toute la documentation technique est dans le dossier `doc/` :

| Document | Contenu |
|----------|---------|
| [Installation](doc/installation.md) | Pré-requis, installation pas à pas, symlinks |
| [Utilisation](doc/utilisation.md) | Menu interactif, arguments CLI, jobs, planification cron |
| [Configuration](doc/configuration.md) | Fichiers locaux, variables, hiérarchie de configuration |
| [Notifications](doc/notifications.md) | Email via msmtp, Discord via webhook |
| [Mise à jour et debug](doc/mise-a-jour.md) | Système de MAJ, codes d'erreur, logs |

## En un coup d'oeil

```bash
# Interactif : le menu vous guide
rclone_homelab

# Simulation avant de se lancer
rclone_homelab --dry-run

# Automatique avec rapport par mail
rclone_homelab --auto --mailto=admin@monserveur.local

# La totale : auto + mail + Discord + simulation
rclone_homelab --auto --dry-run --mailto=admin@monserveur.local --discord-url=https://discord.com/api/webhooks/...
```

---

_Un projet open source. Contributions bienvenues._

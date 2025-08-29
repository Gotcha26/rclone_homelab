# rclone_homelab
## _MON script de synchronisation **Proxmox - Freebox - Cloud**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script [rclone](https://rclone.org/).


## Fonctions principales
- ✅ Fonctionne aussi bien de manière autonome (cron) ou manuel
- ✅ Multi jobs
- ✅ Récursif
- ✅ Détecte des problèmes d'accès aux dossiers
- ✅ Affiche des informations utiles mais compactes
- ✅ Résume la tâche effectuée
- ❗ A besoin de l'outil rclone pour fonctionner.
- ✅ Persistance limitée à 15 jours pour les fichiers de logs
- ✅ Coloration synthaxique
- ❗ Vous rend riche, beau et irresistible
- ✅ Durée de conservation des logs : 15 jours par défaut.
- ℹ️ Vous pouvez appeler le script depuis n'importe où (root inclu)
- ✅ Accèpte les arguments de rclone depuis l'appel du script
- ✅ Notification par mail si msmtp est installé/configuré
- ✅ Notifications Discord possibles via un webhook
- ✅ Système de vérification de mises à jour


## Installation pas à pas [LXC - Debian : compatible]
1. Création d'un dossier dédié
```
mkdir -p /opt/rclone_homelab
```
2. Se placer dedans
```
cd /opt/rclone_homelab
```
3. Cloner le dépôt
```
git clone https://github.com/Gotcha26/rclone_homelab.git .
```
⚠ Le `.` final permet de cloner dans le dossier courant sans créer un sous-dossier supplémentaire.

4. Rendre le script exécutable
```
chmod +x rclone_sync_main.sh
```
5. Ajouter un symlink (raccourcis) pour un accès global afin de pour pouvoir lancer la commande simplement avec `rclone_homelab` :
```
ln -s /opt/rclone_homelab/rclone_sync_main.sh /usr/local/bin/rclone_homelab
```
6. Vérifier l'installation
```
which rclone_homelab
# /usr/local/bin/rclone_homelab

rclone_homelab --help
# script avec ses options
```
7. Pour revenir à votre "home"
```
cd
```

### Mise à jour
Système directement intégré dans le script. Vous averti si une nouvelle version est disponnible.  
- Pour mettre à jour vers la dernière version (tag) :  
`rclone_homelabe --update-tag`           → mettre à jour vers la dernière realse stable

- Pour obtenir les dernières améliorations **BETA**  
`rclone_holemab --update-forced`         → force la mise à jour de la branche main  
`rclone_holemab --update-forced on_work` → force la mise à jour de la branche on_work
Si --update-forced n’est pas présent, le script continue à vérifier le dernier tag comme avant.


## Utilisation

Ce script peut être lancé de manière manuelle directement via le terminal Shell cmd tout simplement en l'appelant :
```
rclone_homelab
```
Des arguments (voir [Arguments](#arguments)) peuvent être utilisés.


## Jobs
Les jobs ne sont pas moins que les directives dédiées pour rclone.

Le script attends 3 arguments minimum pour faire **un job**.  
Pour simplifier la vie, ces *jobs* sont à écrire à l'avance dans un fichier à placer **à coté du script** (même dossier).  
Ce fichier du nom de `rclone_sync_jobs.txt` contiendra **1 ligne par job**.  

###### Exemples :
`nano /opt/rclone_homelab/rclone_sync_jobs.txt`
```ini
<lien_symbolique_source>|<remote_rclone:dossier/sous_dossier>
/srv/backups|onedrive_gotcha:Homelab_backups
```

###### Explications :
Chaque job est constitué d'un ensemble de 2 arguments séparés par un symbole "pipe" `|` ainsi que d'un sous-argument introduit par le symbole `:`
- Le premier argument constitue le dossier d'origine.
Celui qui sera copié et pris pour référence. Vous pouvez l'indiquer "en dur" avec son chemin absolu ou via un symlink (Proxmox).
- Le second argument consiste à indiquer quel *remote* (précédemment paramétré dans via `rclone config`) est à utiliser.
rclone permettant d'en configurer une multitude, il faut bien préciser lequel est à utiliser.
- Le présence du symbole `:` passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud** (distant).  
Dans mon exemple il se trouve à la racine mais vous pourriez décider d'une arborescence plus compliquée.

###### A retenir :
- 1 ligne = 1 job
- <dossier_source>`|`<remote_rclone>`:`dossier_destination/sous_dossier>


## Arguments 
Ils sont optionnels au lancement de `rclone_sync_jobs.sh`
Argument | Explication
--- | ---
  --auto        | Permet simplement de supprimer le logo (bannière).
  --dry-run     | Simule la synchronisation sans transférer ni supprimer de fichiers.
  -h, --help    | Affiche cette humble aide
  --mailto=<mon_adresse@mail.com>    | Permet d'envoyer un rapport par mail à l'adresse indiquée via msmtp


### Envoi d'emails
En association avec l'utilitaire SMTP [msmtp](https://github.com/marlam/msmtp), l'envoi d'email est possible.  
La commande pour éditer son fichier de configuration est : `nano /etc/msmtprc`


## Lancement / Appel
###### Exemple d'appels du script
```
rclone_homelab --dry-run
rclone_homelab --auto --mailto=toto@mail.com --dry-run
rclone_homelab -h
```

## rclone
L'outil rclone est indispensable.  
Pour le [télécharger](https://rclone.org/downloads/) sur Debian (LXC) : `apt install rclone -y`  
Il s'installe normalement dans `/usr/bin/rclone`.

### Personnaliser rclone
Le script rclone dispose d'énormément d'options !  
📖 Lisez la [documentation](https://rclone.org/commands/rclone/) !  
Pour adapter selon vos besoins, il est possible de :
* [Ponctuel] Simplement ajouter l'argument rclone dans vos arguments de lancement.
* [Durable] Modifier `nano /opt/rclone_homelab/rclone_sync_conf.sh` pour trouver la section `# === Options rclone ===`  
Là vous pourrez mettre/enlever vos propores options.


### Notifications Discord
Moyennent l'edition du fichier `nano rclone_sync_conf.sh` vous y trouvere en tout début l'endroit pour ajouter l'URL du *webhook* Discord afin de faire afficher l'information pour __un message par job__.
```
DISCORD_WEBHOOK_URL="<URL_DISCORD_WEBHOOK>"
```


### Tâche Cron
Pour exécuter une tache de manière programmée, rien de tel que l'utilitaire simpliste : CronTab  
Pour ajouter une tâche, la commmande est : `crontab -e`  
Exemple de commande pour une exécution tous les jours à 04h00 :
```
0 4 * * * /opt/rclone_homelab/rclone_sync_main.sh --auto --mailto=<votre_adresse@mail.com> --dry-run >> /var/log/rclone_cron.log 2>&1
```
- **/opt/rclone_homelab/rclone_sync_main.sh** Il est préférable de saisir le chemin en entier et non le symlink vers le script.
- **--auto --mailto=<votre_adresse@mail.com> --dry-run** Options du script
- **>> /var/log/rclone_cron.log 2>&1** [OPTIONNEL] redirection vers un fichier journal, au cas ou... contiendra l'équivalent de c equi est affiché dans la fenêtre de terminal Shell.

## Recommandations (générales)
- Ne pas utilser d'outils ou de script à la base d'un noeud Proxmox. Vous risquez de bloquer toute votre installation !
- Privilégiez toujours un conteneur LXC ou une VM. Plus facile à maintenir et à isoler.
- Utilisez les sauvegardes pour votre installation Proxmox avant toute modification. C'est facile faire et à restaurer !


## Debogage
| Ligne / Bloc                                 | Cause                                         | `ERROR_CODE` |
| -------------------------------------------- | --------------------------------------------- | ------------ |
| Création de `$TMP_RCLONE` échouée            | Impossible de créer le dossier temporaire     | 1            |
| Création de `$LOG_DIR` échouée               | Impossible de créer le dossier de logs        | 2            |
| `$JOBS_FILE` introuvable                     | Fichier jobs absent                           | 3            |
| `$JOBS_FILE` non lisible                     | Fichier jobs présent mais illisible           | 4            |
| `$TMP_RCLONE` non trouvé (après vérif)       | Le dossier temporaire n’existe pas après tout | 5            |
| `$MSG_JOB_LINE_INVALID` invalide             | Fichier jobs présente une ligne illisible     | 6            |
| `$MSG_SRC_NOT_FOUND` non trouvé              | Dossier source (jobs) non trouvé              | 7            |
| Problème avec le processus PID rclone        | Sérieuse                                      | 8            |
| `$MSG_REMOTE_UNKNOW` introuvable ou invalide | Configuration remote ou argument incorrect    | 9            |
| Vérification présence rclone                 | rclone non présent ou injoignable             | 10           | 
| Vérification `$MAIL_TO`                      | Mauvaise saisie de l'adresse email            | 11           | 

  
### Logs
Ils sont purgés tous les 15 jours par défaut.
```
/opt/rclone_homelab/logs/main_xxx.log    <-- Capture la fenêtre du terminal
/opt/rclone_homelab/logs/rclone_xxx.log  <-- Capture le niveau INFO de rclone
/opt/rclone_homelab/logs/msmtp_xxx.log   <-- Capture les paramètres de msmtp
```


## A faire / Ajouter
- Internationnalisation : *wait and see...*

### Petites infos
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).  
NotePad++ (avec plugin "Compare")  
https://dillinger.io (pour la rédaction du présent Readme)  
https://stackedit.io (pour l'aide sur le markedown) Je pourrais me passer de dellinger en plus...  
https://emojikeyboard.org/ (Pour les émojis)  
https://www.desmoulins.fr (Pour ma bannière ASCII)

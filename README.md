# rclone_homelab
## _MON script de synchronisation **rclone_sync_jobs.sh**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script [rclone](https://rclone.org/).

## Fonctions principales
- ✅ Fonctionne aussi bien de manière autonome (cron) ou manuel
- ✅ Multi jobs
- ✅ Récursif
- ✅ Détecte des problèmes d'accès aux dossiers
- ✅ Affiche des informations utiles mais compactes
- ✅ Résume la tâche effectuée
- ❌ Ecrit des logs séparés pour une lecture fluide (INFOS) ou précise (DEBUG)
- ✅ Persistance limitée à 15 jours pour les fichiers de logs
- ✅ Coloration synthaxique
- ❗ Vous rend riche, beau et irresistible
- ✅ Durée de conservation des logs : 15 jours par défaut.

## Installation pas à pas
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
git clone --branch v2 https://github.com/Gotcha26/rclone_homelab.git .

git clone https://github.com/Gotcha26/rclone_homelab.git .
```
⚠ Le `.` final permet de cloner dans le dossier courant sans créer un sous-dossier supplémentaire.

4. Rendre le script exécutable
```
chmod +x rclone_sync_main.sh
```
5. Ajouter un symlink pour un accès global
Pour pouvoir lancer la commande simplement avec `rclone_homelab` :
```
ln -s /opt/rclone_homelab/rclone_sync_main.sh /usr/local/bin/rclone_homelab
```
6. Vérifier
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
Pour mettre à jour facilement l'utilitaire depuis GitHub :
```
cd /opt/rclone_homelab
git pull origin v2
```

### Mise à jour forcée (autre branche)
```
cd /opt/rclone_homelab
```
```
git fetch origin
git reset --hard origin/v2
chmod +x rclone_sync_main.sh
```

## Utilisation

Ce script peut être lancé de manière manuelle directement via le terminal Shell cmd tout simplement en l'appelant :
```
rclone_homelab
```
Des arguments (voir [Arguments](#arguments)) peuvent être utilisés.

## Jobs
Les jobs ne sont pas moins qu'une suite d'instructions contenant les informations pour une exécution facilité.

Le script attends 2 arguments minimum pour faire **un job**.  
Pour simplifier la vie, ces *jobs* sont à écrire à l'avance dans un fichier à placer **à coté du script** (même dossier).  
Ce fichier du nom de `rclone_sync_jobs.txt` contiendra **1 ligne par job**.  

###### Exemples :
`nano /opt/rclone_homelab/rclone_jobs.txt`
```ini
<lien_symbolique_source>|<remote rclone:dossier/sous_dossier>
/srv/backups|onedrive_gotcha:Homelab_backups
```

###### Explications :
Chaque job est constitué de 2 arguments séparés par un symbole "pipe" `|` ainsi que d'un sous-argument introduit par `:`
- En premier argument, c'est le lien symbolique pour atteindre le dossier physique stocké sur notre serveur Proxmox auquel nous avons accès.
Il aura été paramétré précédemment.
- Le second argument consiste à indiquer quel *remote* (précédemment paramétré dans via `rclone config`) est à utiliser. rclone permettant d'en configurer une multitude, ici nous sélectionnons celui qui a déjà été configuré.
- Le présence du symbole `:` passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud**.  
Dans mon exemple il se trouve à la racine mais vous pourriez décider d'une arborescence plus compliquée.

###### A retenir :
- 1 ligne = 1 job
- <lien_symbolique_source>`|`<remote_rclone>`:`dossier/sous_dossier>

## Lancement / Appel
Exemple d'appel du script :
```
rclone_homelab --dry-run
rclone_homelab --auto --mailto=toto@mail.com --dry-run
rclone_homelab -h
```

## Envoi d'emails
En association avec l'utilitaire SMTP [msmtp](https://github.com/marlam/msmtp), l'envoi d'email est possible.  
Veuillez vous référer à cet utilitaire pour le configurer (très simple).

### Arguments 
Ils sont optionnels au lancement de `rclone_sync_jobs.sh`
Argument | Explication
--- | ---
  --auto        | Permet simplement de supprimer le logo (bannière).
  --dry-run     | Simule la synchronisation sans transférer ni supprimer de fichiers.
  -h, --help    | Affiche cette humble aide
  --mailto=<mon_adresse@mail.com>    | Permet d'envoyer un rapport par mail à l'adresse indiquée via msmtp

## Personnaliser rclone
Le script rclone dispose d'énormément d'options !  
📖 Lisez la [documentation](https://rclone.org/commands/rclone/) !  
Pour adapter selon vos besoins, il est possible de modifier `nano /opt/rclone_homelab/rclone_sync_conf.sh` pour trouver la section `# === Options rclone ===`  
Là vous pourrez mettre/enlever vos propores options.

## Recommandations (générales)
- Ne pas utilser d'outils ou de script à la base d'un noeud Proxmox. Vous risquez de bloquer toute votre installation !
- Privilégiez toujours un conteneur LXC ou une VM. Plus facile à maintenir et à isoler.
- Utilisez les sauvegardes Proxmox avant toute modification. C'est facile faire et à restaurer !

## Debogage
| Ligne / Bloc                           | Cause                                         | `ERROR_CODE` |
| -------------------------------------- | --------------------------------------------- | ------------ |
| Création de `$TMP_RCLONE` échouée      | Impossible de créer le dossier temporaire     | 8            |
| Création de `$LOG_DIR` échouée         | Impossible de créer le dossier de logs        | 8            |
| `$JOBS_FILE` introuvable               | Fichier jobs absent                           | 1            |
| `$JOBS_FILE` non lisible               | Fichier jobs présent mais illisible           | 2            |
| `$TMP_RCLONE` non trouvé (après vérif) | Le dossier temporaire n’existe pas après tout | 7            |
  
## A faire / Ajouter
- Scinder le fichier pour arrêter l'aspect monolithique
- Internationnalisation : *wait and see...*

### Petites infos
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).  
NotePad++ (avec plugin "Compare")  
https://dillinger.io (pour la rédaction du présent Readme)  
https://stackedit.io (pour l'aide sur le markedown) Je pourrais me passer de dellinger en plus...  
https://emojikeyboard.org/ (Pour les émojis)  
https://www.desmoulins.fr (Pour ma bannière ASCII)

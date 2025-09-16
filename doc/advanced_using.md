# Utilisation avancée

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
chmod +x /opt/rclone_homelab/main.sh
```
5. Ajouter un symlink (raccourcis) pour un accès global afin de pour pouvoir lancer la commande simplement avec `rclone_homelab` :
```
ln -sf /opt/rclone_homelab/main.sh /usr/local/bin/rclone_homelab
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



## Configuration local

Ensemble de fichiers locaux qui ne sont pas écrasés lors des mises à jour (sauf instruction express et délibérée.)
```
├── local/                    # Espace utilisateur, jamais écrasé
│   ├── jobs.conf             # Jobs persos
│   ├── settings.conf         # Overrides de config
│   └── secrets.env           # Identifiants, tokens msmtp, etc. (EXPERIMENTAL)
```



## Envoi d'emails

1. Le fichier de configuration de msmtp peux se trouver à plusieurs endroits.
Dans le doute, utilisez le menu de **rclone_homelab**.
- `nano /etc/msmtprc`
- `nano /home/<user>/.msmtprc`
- `nano $MSMTPRC`

2. Son contenu ressemble à ceci :
```
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail_1
host           smtp.gmail.com
port           587
from           masuperadresse@gmail.com
user           masuperadresse@gmail.com
password       egknnbapmkvftwnt

account default : gmail_1
```
Le password pour gmail n'est autre que le mot de passe des application accessible uniquement si  
l'authentification à 2 facteurs (AO2F) est activé sur votre compte.  
L'URL pour générer le mot de passe est : https://myaccount.google.com/apppasswords

3. Pour restrindre les droits sur le fichier au seul propriétaire :
```
chmod 600 /home/<user>/.msmtprc
```



## Mise à jour

En ligne de commande, il est possible de forcer la mise à jour systématique via l'argument : `--force-update`  
La mise à jour sera effectué à la fin du traitement normal afin d'éviter tout problème de fichiers.

- Pour forcer à mettre à jour vers la dernière version (tag/release) :  
`rclone_homelab --force-update`           → mettre à jour vers la dernière release stable  
Dans le cadre d'une installation standard, va installer la dernière **release**.

- Pour obtenir les dernières améliorations **BETA**  
`rclone_holemab --force-update`           → force la mise à jour sur la branche men cours.  
`rclone_holemab --force-update <branche>` → force la mise à jour de la branche *branche*.
Si --force-update n’est pas présent, le script continue à vérifier le dernier tag comme avant.

- Une fichier de mise à jour "/update/standalone_updater.sh" est là permettant d'effectuer une mise à jour de manière indépendante du script rclone_homelab pour qu'en cas de soucis sérieux, une remise à niveau puisse être possible en appelant tout simplement le fichier directement `/opt/rclone_homelab/update/standalone_updater.sh` ou via son symlink (installé via install.sh) qui est : `rclone_homelab-updater` qui dispose d'un argument `--force` pour repartir sur un écrasement/suppression complet du répertoire d'installation !



## Debogage (ERROR_CODE)
| E | Ligne / Bloc                                 | Cause                                         |
| - | -------------------------------------------- | --------------------------------------------- |
|  1| Création de `$DIR_TMP` échouée               | Impossible de créer le dossier temporaire     |
|  2| Création de `$DIR_LOG` échouée               | Impossible de créer le dossier de logs        |
|  3| `$JOBS_FILE` introuvable                     | Fichier jobs absent (*)                       |
|  4| `$JOBS_FILE` non lisible                     | Fichier jobs présent mais illisible (*)       |
|  5|                                              |                                               |
|  6| Remote rclone invalide/mal configuré         | Remote mal écrit ou introuvalble              |
|  7| `$MSG_SRC_NOT_FOUND` non trouvé              | Dossier source (jobs) non trouvé              |
|  8| Problème avec le processus PID rclone        | Sérieuse                                      |
|  9|                                              |                                               |
| 10| `msmtp` Vérification présence msmtp          | Installation de msmtp impossible              |
| 11| `rclone` Vérification présence rclone        | rclone non présent ou injoignable             | 
| 12| `RCLONE_CONFIG_FILE` Configuration rclone    | rclone non ou mal configuré                   | 
| 13| Vérification `$MAIL_TO`                      | Mauvaise saisie de l'adresse email            |
| 14| Pb. de token pour Onedrive / Google Drive    | Token invalide, refaire la configuration      |
| 20| `init_config_local` Copie imp. > $local_conf | Droits, blocage...                            |
| 21| `init_config_local` Renommage imp.           | Droits, blocage...                            |
| 22| `check_msmtp_config` Configuration           | Configuration absente (*)                     |
| 23| `check_msmtp_config` Configuration           | Configuration absente (*)                     |


  
### Logs
Les logs sont conservéq pour une durée maximale de 15 jours.  
Le log principal capture tout sauf l'affichage d'édition des fichiers.
```
/opt/rclone_homelab/logs/main_xxx.log    <-- Capture la fenêtre du terminal
/opt/rclone_homelab/logs/rclone_xxx.log  <-- Capture le niveau INFO de rclone
/opt/rclone_homelab/logs/msmtp_xxx.log   <-- Capture les paramètres de msmtp
```
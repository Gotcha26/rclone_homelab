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

4. Rendre le script exécutable (+1 fichier pour mise à jour en standalone)
```
chmod +x /opt/rclone_homelab/main.sh
chmod +x /opt/rclone_homelab/update/standalone_updater.sh
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
├── local/                        # Espace utilisateur, jamais écrasé
│   ├── jobs.conf                 # Nécessaire - Jobs persos (Nécessaire)
│   ├── config.local.conf         # Optionnel - Overrides de config (Optionnel)
│   └── secrets.env               # Optionnel - Identifiants, tokens msmtp, etc. (Optionnel)
```



## Utilisation de l'éditeur "micro"
Choix rendu possible lors de l'installation `instal.sh` *(curl)*.  
Les raccourcis clavier sont trouvables via ce lien : https://doc.ubuntu-fr.org/micro



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
Si `--force-update` n’est pas présent, le script continue à vérifier le dernier tag comme avant.  
Si `--force-update main` (**BETA testeur**) le script vous demandera de confirmer la mise à niveau vers le dernier commit (HEAD) de la branch stable "main" => risque d'instabilité !

- Une fichier de mise à jour "/update/standalone_updater.sh" est là permettant d'effectuer une mise à jour de manière indépendante du script rclone_homelab pour qu'en cas de soucis sérieux, une remise à niveau puisse être possible en appelant tout simplement le fichier directement `/opt/rclone_homelab/update/standalone_updater.sh` ou via son symlink (installé via install.sh) qui est : `rclone_homelab-updater` qui dispose d'un argument `--force` pour repartir sur un écrasement/suppression complet du répertoire d'installation !  
`rclone_homelab-updater` détectera dans la mesure du possible sur quelle branche vous êtes pour installer la même branche.

- Lors des mises à jour via GitHub, les dossiers `logs/` et/ou `tmps/` sont effacés.



## Debogage (DIE / ERROR_CODE)
| E | Fonction | Cause | Bloquant |
| - | - | -|-|
|  5|create_temp_dirs() |Création du dossier `/tmps` impossible. |☑|
|  6|create_temp_dirs() |Création du dossier `/logs` impossible. |☑|
|  7|check_jobs_file() |Fichier introuvable. |☑|
|  8|check_jobs_file() |Fichier non lisible. |☑|
|  9|check_jobs_file() |Fichier vide ou aucun jobs trouvé. |☑|
| 10|install_rclone() |Erreur lors de l'installation |☑|
| 11|install_rclone() |Installation rejettée par l'utilisateur |☑|
| 12|parseur principal |--mailto fourni mais vide ! |☑|
| 13|parseur principal |--mailto mal formé. |☑|
| 14|install_msmtp() |Problème lors de l'installation. |☑|
| 20|check_and_prepare_email() |`check_mail_format()` --mailto non accépté. |☑|
| 21|check_and_prepare_email() `msmtp`|Absent, non installé. |☑|
| 22|check_and_prepare_email() `msmtp`|Requis, rejetté par l'utilisateur. |☑|
| 23|check_and_prepare_email() `msmtp`|Configuration absente/vide. |☑|
| 24|check_and_prepare_email() `msmtp`|Configuration rejetté par l'utilisateur. |☑|
| 25|check_and_prepare_email() `msmtp`|Configuration absente/vide. |☑|
| 26|check_and_prepare_email() `msmtp`|Configuration rejetté par l'utilisateur. |☑|
| 89|menu_validation_local_variables() |Bloqué par l'utilisateur, variable à corriger |☑|
| 90|check_src() |Dossier source (jobs) non trouvé |-|
| 91|check_remotes() `remote`| Manquant/inconnu/injoignable |-|
| 92|check_remotes() `token` | OneDrive/Google en lecture seule |-|
| 93|check_remotes() `--dry-run` | Option incompatible avec le remote CIFS/SMB/local |-|


  
### Logs
Les logs sont conservéq pour une durée maximale de 15 jours.  
Le log principal capture tout sauf l'affichage d'édition des fichiers.
```
/opt/rclone_homelab/logs/main_xxx.log    <-- Capture la fenêtre du terminal
/opt/rclone_homelab/logs/rclone_xxx.log  <-- Capture le niveau INFO de rclone
/opt/rclone_homelab/logs/msmtp_xxx.log   <-- Capture les paramètres de msmtp
```
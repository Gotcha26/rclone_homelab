# rclone_homelab
## _MON script de synchronisation **rclone_sync_jobs.sh**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script rclone.

## Fonctions principales
- ✅ Fonctionne aussi bien de manière autonome (cron) ou manuel
- ✅ Multi jobs
- ✅ Récursif
- ✅ Détecte des problèmes d'accès aux dossiers
- ✅ Affiche des informations utiles mais compactes
- ✅ Résume la tâche effectuée
- ❌ Ecrit des logs séparés pour une lecture fluide (INFOS) ou précise (DEBUG)
- ⚠️ Persistance limitée à 15 jours pour les fichiers de logs
- ✅ Coloration synthaxique
- ❌ Vous rend riche, beau et irresistible

## Utilisation
Le script est à rendre executable via la commande :
```
chmod +x /root/rclone_sync_jobs.sh
```
*Dans le cas où le script est installé avec `root`...*

Ce script peut être lancé de manière manuelle directement via l'instance Shell cmd tout simplement en l'appelant.  
Des arguments (voir [Arguments](#arguments)) peuvent être utilisés.

## Jobs
Le script attends 2 arguments minimum pour faire **un job**.  
Pour simplifier la vie, ces *jobs* sont à écrire à l'avance dans un fichier à placer **à coté du script** (même dossier).  
Ce fichier du nom de `rclone_sync_jobs.txt` contiendra **1 ligne par job**.  

###### Exemples :
```ini
rclone_jobs.txt
<lien_symbolique_source>|<remote rclone:dossier/sous_dossier>
/srv/backups|onedrive_gotcha:Homelab_backups
```

###### Explications :
Chaque job est constitué de 2 arguments séparés par un symbole "pipe" `|`
- En premier argument, c'est le lien symbolique pour atteindre le dossier physique stocké sur notre serveur Proxmox auquel nous avons accès.
Il aura été paramétré précédemment.
- Le second argument consiste à indiquer quel *remote* (précédemment paramétré dans via `rclone config`) est à utiliser. rclone permettant d'en configurer une multitude, ici nous sélectionnons celui qui a déjà été configuré.
Le présence du symbole `:` passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud**. Dans mon exemple il se trouve à la racine mais vous pourriez décider d'une arborescence plus compliquée.

###### A retenir :
- 1 ligne = 1 job
- <lien_symbolique_source>`|`<remote_rclone>`:`dossier/sous_dossier>

## Lancement / Appel
Exemple d'appel du script :
```
./rclone_sync_job.sh --dry-run
./rclone_sync_job.sh --auto --mailto=toto@mail.com --dry-run
./rclone_sync_job.sh -h
```

## Envoi d'emails
En association avec [msmtp](https://github.com/marlam/msmtp), l'envoi d'email est possible.  
Veuillez vous référer à cet utilitaire pour le configurer (très simple).

### Arguments 
Ils sont optionnels au lancement de `rclone_sync_jobs.sh`
Argument | Explication
- | -
  --auto        | Permet simplement de supprimer le logo (bannière).
  --dry-run     | Simule la synchronisation sans transférer ni supprimer de fichiers.
  -h, --help    | Affiche cette humble aide
  --mailto=<mon_adresse@mail.com>    | Permet d'envoyer un rapport par mail à l'adresse indiquée via msmtp

## Recommandations
- Ne pas utilser d'outils ou de script à la base d'un noeud Proxmox.
- Privilégiez toujours un conteneur LXC ou une VM.
- Utilisez les sauvegardes avant toute modification, c'est facile à restaurer !

  
## A faire / Ajouter
- Mettre la durée de conservation comme un argument de configuration en tête du fichier (configuration)
- Ajouter une en-tête personnalisée mais uniquement lors d'une exécution manuel (affichage cmd)
- Fonction d'envoi d'emails 
- Gérer l'absence de fichiers à synchroniser
  - Non normal pour un fonctionnement auto
  - Pas anormal pour un fonctionnement manuel (tests)
- Coloration synthaxique dans l'email html
- Joindre le fichier "DEBUG" uniquement en cas d'erreur dans l'exécution de rclone (pas de fichier à joindre en cas d'erreur autre)

## Petites infos
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).  
NotePad++ (avec plugin "Compare")  
https://dillinger.io (pour la rédaction du présent Readme)  
https://stackedit.io (pour l'aide sur le markedown) Je pourrais me passer de dellinger en plus...  
https://emojikeyboard.org/ (Pour les émojis)  
https://www.desmoulins.fr (Pour ma bannière ASCII)

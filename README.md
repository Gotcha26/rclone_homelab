# rclone_homelab
## _MON script de synchronisation **rclone_sync_jobs.sh**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script rclone.

## Fonctions principales
- Fonctionne aussi bien de manière autonome comment manuelle
- Multi jobs
- Récursif
- Détecte des problèmes d'accès aux dossiers
- Affiche des informations utiles mais compactes
- Affiche les arguments utilisés
- Résume la tâche effectuée
- Ecrit des logs séparés pour une lecture fluide (INFOS) ou précise (DEBUG)
- Persistance limitée à 15 jours pour les fichiers de logs
- Coloration synthaxique (cmd)

## Utilisation
Le script est à rendre executable via la commande :
```
chmod +x /root/rclone_sync_jobs.sh
```
Dans le cas où le script est installé avec `root`...

Ce script peut être lancé de manière manuelle directement via l'instance Shell cmd tout simplement en l'appelant.  
Des arguments (voir [Arguments](#arguments)) peuvent être utilisés.

## Jobs
Le script attends 2 arguments minimum pour faire **un job**.  
Pour simplifier la vie, ces *jobs* sont à écrire à l'avance dans un fichier à placer **à coté du script** (même dossier).  
Ce fichier du nom de `rclone_jobs.txt` contiendra **1 ligne par job**.

###### Exemple :
```ini
rclone_jobs.txt
/srv/backups|onedrive_gotcha:Homelab_backups
```

###### Explications :
Chaque job est constitué de 2 arguments séparés par un symbole "pipe" `|`
- En premier argument, c'est le lien symbolique pour atteindre le dossier physique stocké sur notre serveur Proxmox auquel nous avons accès.
Il a été paramétré précédemment.
- Le second argument consiste à indiquer quel *remote* (précédemment paramétré dans rclone) est à utiliser. rclone permettant d'en configurer une multitude, ici nous sélectionnons celui qui a déjà été configuré.
Le présence du symbole `:` passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud**. Dans mon exemple il se trouve à la racine mais vous pourriez décider de placer dans une arborescence plus compliquée.

###### A retenir :
- 1 ligne = 1 job
- <lien symbolique source>`|`<remote rclone`:`dossier/sous_dossier>

### Arguments 
Ils sont optionnels au lancement de `rclone_sync_jobs.sh`
Argument | Explication
- | -
  --dry-run     | simulateur (ne fait pas d'action)
  --auto        | mode automatique (ex: tâche cron) -> activera futur envoi email
  -h, --help    | affiche cette humble aide

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

## Petite info
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).

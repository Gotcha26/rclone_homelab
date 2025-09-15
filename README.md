# rclone_homelab

### _MON script de synchronisation **Proxmox - Freebox - Cloud**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script [rclone](https://rclone.org/).


### Fonctions principales
- ✅ Permet d'automatiser la synchronisations d'élements entre ordinateurs/services/coulds
- ✅ Multi jobs
- ✅ Utilisation simplifié via un menu
- ✅ Compatible 100% en ligne de commandes

### Fonctions secondaires
- ✅ Fonctionne avec CRON TAB
- ✅ Récursif
- ✅ Symlink : `rclone_homelab`
- ✅ Détecte des problèmes d'accès aux dossiers
- ✅ Affiche des informations utiles mais compactes
- ✅ Résume la tâche effectuée
- ✅ Notification par mail si msmtp est installé/configuré
- ✅ Coloration synthaxique à l'écran et dans les mails
- ✅ Accèpte les arguments de rclone depuis l'appel du script
- ✅ Fichiers de configuration local pour ne rien perdre de vos habitudes
- ✅ Notifications Discord possibles via un webhook
- ✅ Système de vérification et de mises à jour
- ❗ Vous rend riche, beau et irresistible


## Installation
```
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh)
```



## Utilisation

### Sans argument : menu interactif
```
rclone_homelab
```
### En ligne de commandes
Des arguments (voir [Arguments](#arguments)) peuvent être utilisés.
```
rclone_homelab <argument1> <argument2> <argument3>
```



## Arguments 

Ils sont optionnels au lancement de `rclone_homelab` *(`main.sh`)*
Argument | Explication
--- | ---
  -h, --help    | Affiche cette humble aide.
  --auto        | Permet simplement de supprimer le logo (bannière).
  --dry-run     | Simule la synchronisation sans transférer ni supprimer de fichiers.
  --mailto=<mon_adresse@mail.com>    | Permet d'envoyer un rapport par mail à l'adresse indiquée via msmtp.
  --force-update <branch> | Oblige le script à se mettre à jour dans la branche désignée sinon, ce sera la branche en cours par défaut.
  --update-tag <tag> | Va se mettre à jour vers le tag désigné, sinon ce sera la dernière release de la branche en cours par défaut.
  --rclone_opts | Toutes autres arguments seront concidérés comme étant des options pour rclone !



## Envoi d'emails

En association avec l'utilitaire SMTP [msmtp](https://github.com/marlam/msmtp), l'envoi d'email est possible.  
Pour éditer le fichier de configuration, utilisez le menu de rclone_homelab.



## Lancement / Appel

###### Exemple d'appels du script
```
rclone_homelab
rclone_homelab --dry-run
rclone_homelab --auto --mailto=toto@mail.com --dry-run
```



## Jobs (liste des travaux à réaliser)

Les jobs ne sont pas moins que les directives spécifiques aux dossiers / remotes, dédiées **pour rclone**.  
Utilisez le menu de **rclone_homelab** pour générer votre propre fichier. Il contiendra déjà les directives  
pour remplir correctement le dit fichier.

###### Explications :
Chaque job est constitué d'un ensemble de 2 arguments séparés par un symbole "pipe" `|` ainsi que d'un sous-argument introduit par le symbole `:`
- Le premier argument constitue le dossier d'origine.
Celui qui sera copié et pris pour référence. Vous pouvez l'indiquer "en dur" avec son chemin absolu ou via un symlink (Proxmox).
- Le second argument consiste à indiquer quel *remote* (précédemment paramétré dans via `rclone config`) est à utiliser.
rclone permettant d'en configurer une multitude, il faut bien préciser lequel est à utiliser <u>pour ce job</u>.
- Le présence du symbole `:` passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud** (distant).  
Dans mon exemple il se trouve à la racine mais vous pourriez décider d'une arborescence plus compliquée.

###### A retenir :
- 1 ligne = 1 job
- <dossier_source>`|`<remote_rclone>`:`<dossier_destination/sous_dossier>



## Mise à jour

Le script rclone_homelab dispose de son propre outil de mise à jour à jour intégré.  
Vous serez averti qu'une mise à jour est disponible et vous serez invité/guidé dans le processus.










## rclone
L'outil rclone est indispensable.  
Pour le [télécharger](https://rclone.org/downloads/) sur Debian (LXC) : `apt install rclone -y`  
Il s'installe normalement dans `/usr/bin/rclone`.  
Lors de l'installation du rclone_homelab et même durant sans utilisation, si rclone n'est pas présent,  
son installation vous sera proposée car c'est indispensable !

### Personnaliser rclone
Le script rclone dispose d'énormément d'options !  
📖 Lisez la [documentation](https://rclone.org/commands/rclone/) !  
Pour adapter selon vos besoins, il est possible de :
* [Ponctuel] Simplement ajouter l'argument rclone dans vos arguments de lancement.
* [Durable] Modifier `nano /opt/rclone_homelab/config/global.conf` pour trouver la section `# === Options rclone ===`  
Là vous pourrez mettre/enlever vos propores options.


### Notifications Discord
Dispositif (facultatif) permettant via *webhook* (url dans un salon) Discord afin de faire afficher les rapport <u>rclone</u> concernant l'exécution d'un job. Aussi, un batch de plusieurs jobs = plusieurs messages indépendants sur Discord.
1. En argument de lancement (ligne de commandes)
`--discord-webhook <<URL_DISCORD_WEBHOOK>` <== Remplacer *<URL_DISCORD_WEBHOOK>* par votre code. 
2. Dans la configuration local
Passez par le menu pour éditer votre fichier de configuration local pour insérer :
`DISCORD_WEBHOOK_URL="<URL_DISCORD_WEBHOOK>"` <== Remplacer *<URL_DISCORD_WEBHOOK>* par votre code. 



### Tâche Cron
Pour exécuter une tache de manière programmée, rien de tel que l'utilitaire simpliste : CronTab  
Pour ajouter une tâche, la commmande est : `crontab -e`  
Exemple de commande pour une exécution tous les jours à 04h00 :
```
0 4 * * * /opt/rclone_homelab/main.sh --auto --mailto=<votre_adresse@mail.com> --dry-run >> /var/log/rclone_cron.log 2>&1
```
- **/opt/rclone_homelab/main.sh** Il est préférable de saisir le chemin en entier et non le symlink vers le script.
- **--auto --mailto=<votre_adresse@mail.com> --dry-run** Options du script
- **>> /var/log/rclone_cron.log 2>&1** [OPTIONNEL] redirection vers un fichier journal, au cas ou... contiendra l'équivalent de c equi est affiché dans la fenêtre de terminal Shell.

## Recommandations (générales)
- Ne pas utilser d'outils ou de script à la base d'un noeud Proxmox. Vous risquez de bloquer toute votre installation !
- Privilégiez toujours un conteneur LXC ou une VM. Plus facile à maintenir et à isoler.
- Utilisez les sauvegardes pour votre installation Proxmox avant toute modification. C'est facile faire et à restaurer !



## A faire / Ajouter
- [] Internationnalisation : *wait and see...*
- [] Webhook discord à mettre en argument de lancement
- [] Mise à jour des dépendances (rclone, msmtp, gotcha_lib)
- [] Revoir l'installation de rclone depuis mon main.sh
- [] Lors d'une MAJ en ligne de commande, faire cette dernière à la fin du processus normal pour ne rien bloquer.
- [] En cas de MAJ détectée, prévenir via le rapport d'exécution qu'un MAJ est disponnible (mail/discord)
- [x] Metre en varaibles les fichiers locaux conf + dir
- [] Ne plus parler de "configuration locale" mais ed paramètres personnalisés

### Petites infos
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).  
NotePad++ (avec plugin "Compare")  
https://dillinger.io (pour la rédaction du présent Readme)  
https://stackedit.io (pour l'aide sur le markedown) Je pourrais me passer de dellinger en plus...  
https://emojikeyboard.org/ (Pour les émojis)  
https://www.desmoulins.fr (Pour ma bannière ASCII)

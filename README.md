# rclone_homelab

### _MON script de synchronisation **Proxmox - Freebox - Cloud**_
_✌️🥖🔆Fait avec amour dans le sud de la France.❤️️🇫🇷🐓_

Juste un script qui permet de synchroniser un dossier local avec un dossier distant en utilisant le script [rclone](https://rclone.org/).


### Fonctions principales
- ✅ Permet d'automatiser la synchronisations d'élements entre ordinateurs/services/coulds
- ✅ Multi jobs
- ✅ Utilisation simplifié via un menu interactif
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
- ✅ Fichiers de configuration locale pour ne rien perdre de vos habitudes
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
|......Argument......|......Explications......|
| --- | --- |
|`-h`, `--help`  | Affiche cette humble aide. |
|`--auto`        | Ideal pour CronTab, affichage minime, interractions réduite au seuls cas bloquants, ne prend en considération que les élements inscrits dans les fichiers locaux (si présents). |
|`--dry-run`     | Simule la synchronisation sans transférer ni supprimer de fichiers (services cloud uniquement). |
|`--mailto=`     | <adresse@mail.com> Permet d'envoyer un rapport par mail à l'adresse indiquée via msmtp. |
|`--discord-url=`| Adresse weebhook pour affichage dans un salon Discord |
|`--force-update`| Oblige le script à se mettre à jour. Optionnel : branche spécifique via `<branch>` |
|`--discord-url=`| `<url>` Saisir le webhook de Discord pour y recevoir les notifications. |
|`--rclone_opts` | `<opts>` cumulez les options native de rclone ! |



## Envoi d'emails

En association avec l'utilitaire SMTP [msmtp](https://github.com/marlam/msmtp)[^1], l'envoi d'email est possible.  
msmtp est livré par défaut sans aucune configuration. Pour éditer le fichier de configuration, utilisez le menu interactif de rclone_homelab.



## Lancement / Appel

###### Exemple d'appels du script
```
rclone_homelab
rclone_homelab --dry-run
rclone_homelab --auto --mailto=toto@mail.com --dry-run
```



## Menu interactif
Ce *menu* (dit interactif) est là pour faciliter les interactions que vous pouvez avoir avec le script rclone_homelab.  
Pour y accèder, rien de plus simple : appelez **tout simplement** le script principal **sans le moindre argument de lancement !**.  
Donc juste avec : `rclone_homelab` vous arriverez automatiquement sur le menu qui vous proposera différentes options



## Jobs

Les jobs ne sont pas moins que les directives spécifiques aux dossiers / remotes, dédiées **pour rclone**. C'est la liste des travaux à réaliser pour rclone.  
Utilisez le menu interactif de **rclone_homelab** pour générer votre propre fichier. Il contiendra déjà les directives  
pour remplir correctement le dit fichier.

###### Explications :
Chaque job est constitué d'un ensemble de 2 arguments séparés par un symbole "pipe" <`|`> ainsi que d'un sous-argument introduit par le symbole <`:`>
- Le premier argument constitue le dossier d'origine [source].
Il sera copié et pris pour référence. Vous pouvez l'indiquer "en dur" avec son chemin absolu ou via un symlink (Proxmox).
- Le second argument consiste à indiquer quel *remote* [remote] (précédemment paramétré dans via `rclone config`) est à utiliser.
rclone permettant d'en configurer une multitude, il faut bien préciser lequel est à utiliser pour ce job.
- Le présence du symbole <`:`> passe un sous-argument qui indique le chemin du dossier à atteindre dans **le cloud** (distant) [destination].  
Dans mon exemple il se trouve à la racine mais vous pourriez avoir une arborescence plus compliquée sur votre stockage.

###### A retenir :
- 1 ligne = 1 job
- <dossier_source>`|`<remote_rclone>`:`<dossier_destination/sous_dossier>



## Mise à jour

Le script rclone_homelab dispose de son propre outil de mise à jour intégré.  
Vous serez averti qu'une mise à jour est disponible et vous serez invité/guidé dans le processus.

*Un outil déporté pour Git est accessible via `rclone_homelab-updater`*



## rclone
L'outil rclone est indispensable[^1].  
Pour le [télécharger](https://rclone.org/downloads/) sur Debian (LXC) : `apt install rclone -y`  
Il s'installe normalement dans `/usr/bin/rclone`.  
Lors de l'installation de rclone_homelab et même durant sans utilisation, si rclone n'est pas présent,  son installation vous sera proposée car c'est **indispensable !**

### Personnaliser rclone
rclone dispose d'énormément d'options. 📖 Lisez sa [documentation](https://rclone.org/commands/rclone/) !

Pour adapter selon vos besoins, il est possible de :
* **[Ponctuel]** Simplement ajouter l'argument rclone dans vos [arguments](#arguments) lors du lancement.
* **[Durable]** Utilisez le menu interactif pour installer/éditer un fichier pré-rempli pour votre configuration local personalisée.  
Vous y trouverez la section `# === Options rclone ===` => Là vous pourrez mettre/enlever vos propores options.


### Notifications Discord
Dispositif *(facultatif)* permettant via un *webhook* (url dans un salon) de faire afficher les rapport <u>rclone</u> concernant l'exécution d'un job. Aussi, un batch de plusieurs jobs = plusieurs messages indépendants sur Discord.
1. En argument de lancement (ligne de commandes)
`--discord-webhook <<URL_DISCORD_WEBHOOK>` <== Remplacer *<URL_DISCORD_WEBHOOK>* par votre code. 
2. Dans la configuration local
Passez par le menu interactif pour éditer votre fichier de configuration locale afin d'adapter :
`DISCORD_WEBHOOK_URL="<URL_DISCORD_WEBHOOK>"` <== Remplacer *<URL_DISCORD_WEBHOOK>* par votre code. 



### Tâche Cron
Pour exécuter une tache de manière programmée, rien de tel que l'utilitaire simpliste : CronTab  
Pour ajouter une tâche, la commmande est : `crontab -e`  
Exemple de commande pour une exécution tous les jours à 04h00 :
```
0 4 * * * /opt/rclone_homelab/main.sh --auto --mailto=<votre_adresse@mail.com> --dry-run >> /var/log/rclone_cron.log 2>&1
```
| Bloc | Explications |
| --- | --- |
|`/opt/rclone_homelab/main.sh`                        | Il est préférable de saisir le chemin en entier et non le symlink vers le script. |
|`--auto` `--mailto=<votre_adresse@mail.com>` `--dry-run` | [arguments](#arguments) du script (exemples)|
|`>> /var/log/rclone_cron.log 2>&1`                   | **[OPTIONNEL]** redirection vers un fichier journal, au cas ou... contiendra l'équivalent de ce qui est affiché dans la fenêtre de terminal Shell. |

## Recommandations (générales)
- Ne pas utilser d'outils ou de script à la base d'un noeud Proxmox. Vous risquez de bloquer toute votre installation !
- Privilégiez toujours un conteneur LXC ou une VM. Plus facile à maintenir et à isoler.
- Utilisez les sauvegardes pour votre installation Proxmox avant toute modification. C'est facile faire et à restaurer !



## A faire / Ajouter
- [] Internationnalisation : *wait and see...*
- [] Externaliser le débugage au démarrage.
- [] msmtp, utiliser un fichier spécifique + accompte `msmtp --file=/etc/msmtp/accounts.conf --account=backup user@example.com`


### Petites infos
*Bon oui ok*, si j'ai pensé, travaillé, imaginé, sué et perdu quelques heures d'espérance de vie, le travail a été rendu possible grâce aux Chats IA (GPT + Mistral).  
NotePad++ (avec plugin "Compare")  
https://dillinger.io (pour la rédaction du présent Readme)  
https://stackedit.io (pour l'aide sur le markedown) Je pourrais me passer de dellinger en plus...  
https://emojikeyboard.org/ (Pour les émojis)  
https://www.desmoulins.fr (Pour ma bannière ASCII), aussi https://patorjk.com/software/taag/ ou encore http://www.network-science.de/ascii/

[^1]: Proposé lors de l'installation.
# Notifications

> [Retour au README](../README.md) · [Installation](installation.md) · [Utilisation](utilisation.md) · [Configuration](configuration.md) · [Mise à jour et debug](mise-a-jour.md)

---

## Table des matières

- [Statut annoncé](#statut-annoncé)
- [Email via msmtp](#email-via-msmtp)
- [Discord via webhook](#discord-via-webhook)

---

## Statut annoncé

Le sujet du mail et chaque message Discord annoncent l'un de ces statuts :

| Statut | Signification |
| :---: | --- |
| ✅ Sauvegardes vers le cloud réussies | rclone a terminé sans erreur et des fichiers ont été copiés, mis à jour ou supprimés |
| ⚠️ Synchronisation réussie mais aucun fichier transféré | Tout était déjà à jour (aucun job n'a rien eu à faire) |
| ⚠️ Sauvegardes réussies après nouvelle(s) tentative(s) | rclone a rencontré des erreurs passagères mais a fini par réussir en retentant |
| ❌ Des erreurs lors des sauvegardes vers le cloud | Au moins un job a échoué, ou n'a pas pu être lancé (remote absent, source introuvable...) |

Le statut repose sur le **code de retour de rclone**, et non sur la simple présence du mot `ERROR` dans le log : rclone retente seul les opérations ratées (3 tentatives par défaut), et une erreur passagère suivie d'une réussite n'est pas un échec.

- **Mail** : un seul statut global pour l'ensemble des jobs.
- **Discord** : un statut par job.

> Un ⚠️ « après nouvelle(s) tentative(s) » isolé est sans gravité (souvent un aléa côté fournisseur cloud). S'il revient chaque nuit, consultez le log rclone joint et pensez à [mettre à jour rclone](mise-a-jour.md#mettre-à-jour-rclone).

---

## Email via msmtp

### Principe

Rclone Homelab Manager génère un **rapport HTML** après l'exécution de tous les jobs. Ce rapport peut être envoyé par email via [msmtp](https://github.com/marlam/msmtp), un client SMTP léger.

### Installer msmtp

Via le menu interactif (option proposée automatiquement si absent) ou manuellement :

```bash
apt install msmtp msmtp-mta -y
```

### Configurer msmtp

Le fichier de configuration peut se trouver à différents endroits. Utilisez le menu de rclone_homelab pour le créer/éditer, ou éditez-le directement :

```bash
nano ~/.msmtprc
# ou
nano /etc/msmtprc
```

#### Exemple avec Gmail

```
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail_1
host           smtp.gmail.com
port           587
from           votre.adresse@gmail.com
user           votre.adresse@gmail.com
password       abcdefghijklmnop

account default : gmail_1
```

> **Gmail** : le champ `password` attend un **mot de passe d'application**, pas votre mot de passe habituel. L'authentification à 2 facteurs (A2F) doit être activée. Générez le mot de passe sur : [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)

#### Sécuriser le fichier

```bash
chmod 600 ~/.msmtprc
```

### Utiliser l'envoi d'emails

En argument de lancement :

```bash
rclone_homelab --auto --mailto=admin@monserveur.local
```

Ou dans votre configuration locale (`local/config.local.conf`) :

```bash
MAIL_TO=admin@monserveur.local
```

Le rapport HTML inclut :
- Le résultat de chaque job (succès/échec)
- Les logs rclone avec coloration syntaxique
- Un résumé global

### Vérifications automatiques

Avant l'envoi, le script vérifie :
1. Le format de l'adresse email (regex)
2. La présence de msmtp (propose l'installation si absent)
3. L'existence d'un fichier de configuration msmtp valide

---

## Discord via webhook

### Principe

Chaque job terminé peut envoyer une notification sur un salon Discord via un webhook. Le message contient un résumé et le fichier de log est envoyé en pièce jointe.

### Créer un webhook Discord

1. Ouvrez les **paramètres du salon** Discord souhaité
2. Allez dans **Intégrations** → **Webhooks**
3. Cliquez **Nouveau webhook**
4. Copiez l'**URL du webhook**

L'URL ressemble à :
```
https://discord.com/api/webhooks/123456789/ABCdefGHIjklMNOpqrSTUvwxYZ
```

### Utiliser les notifications Discord

En argument de lancement :

```bash
rclone_homelab --auto --discord-url=https://discord.com/api/webhooks/123456789/ABCdefGHIjklMNOpqrSTUvwxYZ
```

Ou dans votre configuration locale (`local/config.local.conf`) :

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123456789/ABCdefGHIjklMNOpqrSTUvwxYZ
```

Ou dans le fichier secrets (`local/secrets.env`) pour ne pas exposer l'URL :

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123456789/ABCdefGHIjklMNOpqrSTUvwxYZ
```

### Pré-requis

`jq` est nécessaire pour construire le payload JSON de manière sécurisée. Installation :

```bash
apt install jq -y
```

### Comportement

- Un message Discord est envoyé **par job** (pas un seul message global)
- Le fichier de log rclone est joint à chaque message
- Le payload JSON est construit via `jq` pour éviter toute injection

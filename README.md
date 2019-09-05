# Plugin Transition Bibliographique pour Koha

Ce plugin vise à faciliter l'import de données dans Koha pour la
transition bibliographique

# Pré-requis

- Koha 18.11 minimum
- Modules Perl:
  - YAML

# Installation

1. Récupérer [la dernière version du
   plugin](https://github.com/biblibre/koha-plugin-transition-bibliographique/releases/latest)
   (fichier .kpz)
2. Installer le plugin via l'interface d'administration de Koha
3. Sur le serveur, copier
   `Koha/Plugin/Com/BibLibre/TransitionBibliographique/config.yaml.sample`
   vers `Koha/Plugin/Com/BibLibre/TransitionBibliographique/config.yaml`
4. Si besoin, modifier `config.yaml`
5. Mettre
   `Koha/Plugin/Com/BibLibre/TransitionBibliographique/cron/job-runner.pl`
   en cronjob.
6. (Optionnel) Mettre
   `Koha/Plugin/Com/BibLibre/TransitionBibliographique/cron/purge.pl` en
   cronjob

# Cronjobs

Tous les cronjobs doivent être lancés quotidiennement, de préférence la nuit
pour ne pas gêner l'utilisation normale de Koha.

Exemple:

```
PERL5LIB=/path/to/koha
KOHA_CONF=/path/to/koha-conf.xml
PATH_TO_PLUGIN=/path/to/plugin

50 22 * * * $PATH_TO_PLUGIN/Koha/Plugin/Com/BibLibre/TransitionBibliographique/cron/purge.pl --older-than=30
0 23 * * * $PATH_TO_PLUGIN/Koha/Plugin/Com/BibLibre/TransitionBibliographique/cron/job-runner.pl
```

# Plugin Transition Bibliographique pour Koha

Ce plugin vise à faciliter l'export et l'import de données dans Koha pour la
transition bibliographique

# Pré-requis

- Koha 18.11 minimum
- Modules Perl:
  - Catmandu
  - Catmandu::Exporter::MARC
  - YAML

# Installation

1. Récupérer la dernière version du plugin (fichier .kpz)
2. Installer le plugin via l'interface d'administration de Koha
3. Sur le serveur, copier
   `Koha/Plugin/Com/BibLibre/TransitionBibliographique/config.yaml.sample`
   vers `Koha/Plugin/Com/BibLibre/TransitionBibliographique/config.yaml`
4. Si besoin, modifier `config.yaml`
5. Mettre `Koha/Plugin/Com/BibLibre/TransitionBibliographique/cron/export.pl`
   en cronjob et lancer manuellement le script une première fois.

#!/bin/bash

mysql -e "DROP TABLE IF EXISTS koha_plugin_com_biblibre_transitionbibliographique_audit_tb;"

mysql -e "
    CREATE TABLE koha_plugin_com_biblibre_transitionbibliographique_audit_tb (
      audit_id int(11) NOT NULL AUTO_INCREMENT,
      timestamp timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP, -- date d exécution de l audit
      check_marcfield_009  tinyint(1) NOT NULL, -- presence du 009
      check_marcfield_010a tinyint(1) NOT NULL,
      check_marcfield_011a tinyint(1) NOT NULL,
      check_marcfield_033a tinyint(1) NOT NULL,
      check_marcfield_073a tinyint(1) NOT NULL,
      check_marcfield_181c tinyint(1) NOT NULL,
      check_marcfield_182c tinyint(1) NOT NULL,
      check_marcfield_183c tinyint(1) NOT NULL,
      check_marcfield_214  tinyint(1)  NOT NULL,
      check_marcfield_219  tinyint(1)  NOT NULL,
      count_marcfield_009  int(11) NOT NULL, -- nombre de 009 renseignés
      count_marcfield_010a int(11) NOT NULL,
      count_marcfield_011a int(11) NOT NULL,
      count_marcfield_033a int(11) NOT NULL,
      count_marcfield_073a int(11) NOT NULL,
      count_marcfield_181c int(11) NOT NULL,
      count_marcfield_182c int(11) NOT NULL,
      count_marcfield_183c int(11) NOT NULL,
      count_marcfield_214  int(11) NOT NULL,
      count_marcfield_219  int(11) NOT NULL,
      count_bnf_ark        int(11) NOT NULL, -- nombre de notices avec un ARK BnF (en 033a)
      count_sudoc_ppn      int(11) NOT NULL, -- nombre de notices avec un PPN Abes (en 009 ou 033a)
      count_ids_in_033a    int(11) NOT NULL,  -- nombre de notices avec autre chose qu un ARK BnF ou PPB
      count_biblios  int(11) NOT NULL, -- nombre de biblio
      count_aligned_biblios  int(11) NOT NULL, -- nombre de biblios considerees comme alignees
      tb_score  int(11) NOT NULL,  -- score peut etre a retirer
      quality_score  int(11) NOT NULL,  -- score de qualite des donnees sera renseigne plus tard
      PRIMARY KEY (audit_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
"

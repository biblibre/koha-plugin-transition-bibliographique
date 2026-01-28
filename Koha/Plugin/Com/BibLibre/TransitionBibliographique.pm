package Koha::Plugin::Com::BibLibre::TransitionBibliographique;

use base qw(Koha::Plugins::Base);

use Modern::Perl;
use utf8;

use Encode;
use JSON;
use List::MoreUtils qw(first_index any none uniq);
use Text::CSV::Encoded;
use Text::CSV;
use YAML qw(LoadFile);

use C4::AuthoritiesMarc qw(GetAuthority ModAuthority);
use C4::Biblio qw(GetFrameworkCode ModBiblio);
use C4::Context;

use Koha::Authorities;
use Koha::Authority;
use Koha::Database;

use Koha::Plugin::Com::BibLibre::TransitionBibliographique::AuthorisedValues qw(
    QUALIF_AUTHORISED_VALUES
    LANG_AUTHORISED_VALUES
    CODEPEB_AUTHORISED_VALUES
);

our $VERSION = "0.4.0";

our $metadata = {
    name            => 'Transition bibliographique',
    author          => 'BibLibre',
    date_authored   => '2019-03-25',
    date_updated    => "2023-12-04",
    minimum_version => '20.1100000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin aims to ease data import into catalogue (biblios and authorities)',
};

my $DEBUG = exists $ENV{'DEBUG'} ? $ENV{'DEBUG'} : 0;

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub install {
    my ($self, $args) = @_;

    my $dbh = C4::Context->dbh;

    my $audit_tb_table = $self->get_qualified_table_name('audit_tb');
    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    my $av_table = $self->get_qualified_table_name('av');
    my $audit_av_table = $self->get_qualified_table_name('audit_av');
    my $audit_auth_table = $self->get_qualified_table_name('audit_auth');

    $dbh->do("DROP TABLE IF EXISTS $audit_tb_table");
    $dbh->do("DROP TABLE IF EXISTS $av_table");

    $dbh->do(qq{
        DROP TABLE IF EXISTS $jobs_logs_table
    });
    $dbh->do(qq{
        DROP TABLE IF EXISTS $jobs_table
    });

    $dbh->do( "
        CREATE TABLE $audit_tb_table (
            audit_id int(11) NOT NULL AUTO_INCREMENT,
            timestamp timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP, -- date d exécution de l audit
            check_marcfield_009  tinyint(1) NOT NULL, -- presence du 009
            check_marcfield_010a tinyint(1) NOT NULL,
            check_marcfield_011a tinyint(1) NOT NULL,
            check_marcfield_029  tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_033a tinyint(1) NOT NULL,
            check_marcfield_073a tinyint(1) NOT NULL,
            check_marcfield_1012 tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_181c tinyint(1) NOT NULL,
            check_marcfield_182c tinyint(1) NOT NULL,
            check_marcfield_183c tinyint(1) NOT NULL,
            check_marcfield_214  tinyint(1) NOT NULL,
            check_marcfield_215b tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_219  tinyint(1) NOT NULL,
            check_marcfield_325  tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_338  tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_371  tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_930j tinyint(1) NOT NULL DEFAULT 0,
            check_marcfield_930j_av_codepeb tinyint(1) NOT NULL DEFAULT 0,
            count_marcfield_003  int(11) NOT NULL DEFAULT 0,
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
    " );

    $dbh->do( "
        CREATE TABLE $av_table (
            category varchar(32) NOT NULL,
            authorised_value varchar(80) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    " );

    $dbh->do(qq{
        CREATE TABLE $jobs_table (
            id SERIAL,
            args BLOB,
            state VARCHAR(128),
            enqueued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            started_at TIMESTAMP NULL,
            finished_at TIMESTAMP NULL,
            PRIMARY KEY (id)
        )
    });

    $dbh->do(qq{
        CREATE TABLE $jobs_logs_table (
            id SERIAL,
            job_id BIGINT UNSIGNED NOT NULL,
            logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            type VARCHAR(255) NULL DEFAULT NULL,
            message TEXT,
            PRIMARY KEY (id),
            CONSTRAINT jobs_logs_fk_job_id
              FOREIGN KEY (job_id) REFERENCES $jobs_table (id)
              ON DELETE CASCADE ON UPDATE CASCADE
        )
    });

    my $sth = $dbh->prepare("INSERT $av_table SET category = ?, authorised_value = ?");
    foreach my $authorised_value (QUALIF_AUTHORISED_VALUES) {
        $sth->execute('qualif', $authorised_value);
    }
    foreach my $authorised_value (LANG_AUTHORISED_VALUES) {
        $sth->execute('LANG', $authorised_value);
    }
    foreach my $authorised_value (CODEPEB_AUTHORISED_VALUES) {
        $sth->execute('CODEPEB', $authorised_value);
    }

    $dbh->do( "
        CREATE TABLE $audit_av_table (
            audit_id INT NOT NULL,
            category varchar(32) NOT NULL,
            authorised_value varchar(80) NOT NULL,
            is_missing tinyint(1) NOT NULL DEFAULT 0,
            is_invalid tinyint(1) NOT NULL DEFAULT 0,
            CONSTRAINT fk_audit_av_audit_id FOREIGN KEY (audit_id) REFERENCES $audit_tb_table (audit_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    " );

    $dbh->do( "
        CREATE TABLE $audit_auth_table (
            audit_id INT NOT NULL,
            authtypecode varchar(10) NOT NULL,
            check_marcfield_1012 tinyint(1) NOT NULL DEFAULT 0,
            CONSTRAINT fk_audit_auth_audit_id FOREIGN KEY (audit_id) REFERENCES $audit_tb_table (audit_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    " );

    return 1;
}

sub uninstall {
    my ($self) = @);

    my $dbh = C4::Context->dbh;

    my $audit_tb_table = $self->get_qualified_table_name('audit_tb');
    my $audit_av_table = $self->get_qualified_table_name('audit_av');
    my $audit_auth_table = $self->get_qualified_table_name('audit_auth');
    my $av_table = $self->get_qualified_table_name('av');
    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');

    $dbh->do("DROP TABLE IF EXISTS $audit_av_table");
    $dbh->do("DROP TABLE IF EXISTS $audit_auth_table");
    $dbh->do("DROP TABLE IF EXISTS $audit_tb_table");
    $dbh->do("DROP TABLE IF EXISTS $av_table");
    $dbh->do("DROP TABLE IF EXISTS $jobs_logs_table");
    $dbh->do("DROP TABLE IF EXISTS $jobs_table");

    return 1;
}

sub upgrade {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $old_version = $self->retrieve_data('__INSTALLED_VERSION__');
    my $audit_tb_table = $self->get_qualified_table_name('audit_tb');
    my $audit_av_table = $self->get_qualified_table_name('audit_av');
    my $audit_auth_table = $self->get_qualified_table_name('audit_auth');
    my $av_table = $self->get_qualified_table_name('av');

    if ($self->_version_compare($old_version, '0.4.0') < 0) {
        # The audit_tb table might not exist if setup-audit-tbiblio.sh was never executed
        # So create the table first if needed
        $dbh->do( "
            CREATE TABLE IF NOT EXISTS $audit_tb_table (
                audit_id int(11) NOT NULL AUTO_INCREMENT,
                timestamp timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
                check_marcfield_009  tinyint(1) NOT NULL,
                check_marcfield_010a tinyint(1) NOT NULL,
                check_marcfield_011a tinyint(1) NOT NULL,
                check_marcfield_033a tinyint(1) NOT NULL,
                check_marcfield_073a tinyint(1) NOT NULL,
                check_marcfield_181c tinyint(1) NOT NULL,
                check_marcfield_182c tinyint(1) NOT NULL,
                check_marcfield_183c tinyint(1) NOT NULL,
                check_marcfield_214  tinyint(1)  NOT NULL,
                check_marcfield_219  tinyint(1)  NOT NULL,
                count_marcfield_009  int(11) NOT NULL,
                count_marcfield_010a int(11) NOT NULL,
                count_marcfield_011a int(11) NOT NULL,
                count_marcfield_033a int(11) NOT NULL,
                count_marcfield_073a int(11) NOT NULL,
                count_marcfield_181c int(11) NOT NULL,
                count_marcfield_182c int(11) NOT NULL,
                count_marcfield_183c int(11) NOT NULL,
                count_marcfield_214  int(11) NOT NULL,
                count_marcfield_219  int(11) NOT NULL,
                count_bnf_ark        int(11) NOT NULL,
                count_sudoc_ppn      int(11) NOT NULL,
                count_ids_in_033a    int(11) NOT NULL,
                count_biblios  int(11) NOT NULL,
                count_aligned_biblios  int(11) NOT NULL,
                tb_score  int(11) NOT NULL,
                quality_score  int(11) NOT NULL,
                PRIMARY KEY (audit_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        " );

        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_029 tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_011a");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_1012 tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_073a");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_215b tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_214");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_325 tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_219");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_338 tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_325");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_371 tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_338");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_930j tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_371");
        $dbh->do("ALTER TABLE $audit_tb_table ADD check_marcfield_930j_av_codepeb tinyint(1) NOT NULL DEFAULT 0 AFTER check_marcfield_930j");
        $dbh->do("ALTER TABLE $audit_tb_table ADD count_marcfield_003 int(11) NOT NULL DEFAULT 0 AFTER check_marcfield_930j_av_codepeb");

        $dbh->do( "
            CREATE TABLE $av_table (
                category varchar(32) NOT NULL,
                authorised_value varchar(80) NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        " );

        my @qualif_authorised_values = qw(
            000 003 005 010 015 018 020 030 040 050 060 065 070 072 075 080 090 100 110 120 130 140 150 160 170 180 190
            195 200 202 205 206 207 210 212 220 230 233 236 240 245 250 255 257 260 270 273 275 280 290 295 300 303 305
            310 320 330 340 350 355 360 365 370 380 385 390 395 400 405 407 410 420 430 440 445 450 460 470 475 480 490
            500 510 520 530 535 540 545 550 552 555 557 560 570 571 573 574 575 580 582 584 587 590 595 600 605 610 620
            630 632 633 635 637 640 650 651 655 660 670 672 673 675 677 678 680 690 695 700 705 710 720 721 723 725 726
            727 730 735 740 750 753 755 760 770 956 958 981 982 983 984 985 996
        );

        my @lang_authorised_values = qw(
            aar abk ace ach ada ady afa afh afr ajm aka akk alb alg amh ang ara arc arm arp art asm ava ave awa aym aze
            bak bam ban baq bel ben ber bis bnt bos bra bre btk bua bug bul bur cai cam cat cau cel chb chi chm chu chv
            cop cor cos cpe cpf cpp cre crp cze dan den deu dra dum dut dyu efi egy eng enm epo esk est ewe fan fao fij
            fin fiu fon fre frm fro fry ful gaa gag gem geo ger gez gil gla gle glg glv gmh goh got grc gre grn guj hat
            hau haw heb hin hit hrv hun ibo ice iku inc ind ine ira iro ita jav jpn jrb kab kan kas kaw kaz khm kik kin
            kir kmb kon kor kur lad lan lao lap lat lav lin lit lug mac mal man mao map mar may mga mic min mis mkh mla
            mlg mlt mni mol mon mos mul mus myn myv nah nai nav ndo nds nep nic niu nno nob non nor nso nub nya oci oji
            ori oss ota paa pal pan pap peo per phi pli pol por pra pro pus que raj rap rar roa roh rom rum run rus sah
            sai sam san scc scn sco scr sem sga sgn sin sit sla slo slv smi smn smo sna snh snk som son spa srp ssa sun
            sux swa swe syr tah tai tam tat tel tgk tgl tha tib tir tmh tog ton tuk tur tut tvl twi uga uig ukr und urd
            uzb vie wel wen wln wol xal xho xxx yid yor zul zxx
        );

        my @codepeb_authorised_values = qw(a b f g s u v);

        my $sth = $dbh->prepare("INSERT $av_table SET category = ?, authorised_value = ?");
        foreach my $authorised_value (@qualif_authorised_values) {
            $sth->execute('qualif', $authorised_value);
        }
        foreach my $authorised_value (@lang_authorised_values) {
            $sth->execute('LANG', $authorised_value);
        }
        foreach my $authorised_value (@codepeb_authorised_values) {
            $sth->execute('CODEPEB', $authorised_value);
        }

        $dbh->do( "
            CREATE TABLE $audit_av_table (
                audit_id INT NOT NULL,
                category varchar(32) NOT NULL,
                authorised_value varchar(80) NOT NULL,
                is_missing tinyint(1) NOT NULL DEFAULT 0,
                is_invalid tinyint(1) NOT NULL DEFAULT 0,
                CONSTRAINT fk_audit_av_audit_id FOREIGN KEY (audit_id) REFERENCES $audit_tb_table (audit_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        " );

        $dbh->do( "
            CREATE TABLE $audit_auth_table (
                audit_id INT NOT NULL,
                authtypecode varchar(10) NOT NULL,
                check_marcfield_1012 tinyint(1) NOT NULL DEFAULT 0,
                CONSTRAINT fk_audit_auth_audit_id FOREIGN KEY (audit_id) REFERENCES $audit_tb_table (audit_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        " );
    }

    return 1;
}

sub configure {
    my ( $self, $args ) = @_;

    my $cgi = $self->{cgi};
    my $dbh = C4::Context->dbh;
    my $av_table = $self->get_qualified_table_name('av');

    if ('POST' eq $cgi->request_method()) {
        my (@qualif_authorised_values, @lang_authorised_values, @codepeb_authorised_values);

        my $csv = Text::CSV->new({ binary => 1 });
        if ( my $fh = $cgi->upload('qualif') ) {
            # ignore headers
            my $line = $csv->getline($fh);

            while ($line = $csv->getline($fh)) {
                next if (@$line == 1 && $line->[0] eq '');
                push @qualif_authorised_values, $line->[0];
            }
        }

        if ( my $fh = $cgi->upload('lang') ) {
            # ignore headers
            my $line = $csv->getline($fh);

            while ($line = $csv->getline($fh)) {
                next if (@$line == 1 && $line->[0] eq '');
                push @lang_authorised_values, $line->[0];
            }
        }

        if ( my $fh = $cgi->upload('codepeb') ) {
            # ignore headers
            my $line = $csv->getline($fh);

            while ($line = $csv->getline($fh)) {
                next if (@$line == 1 && $line->[0] eq '');
                push @codepeb_authorised_values, $line->[0];
            }
        }

        @qualif_authorised_values = sort { $a cmp $b } uniq @qualif_authorised_values;
        @lang_authorised_values = sort { $a cmp $b } uniq @lang_authorised_values;
        @codepeb_authorised_values = sort { $a cmp $b } uniq @codepeb_authorised_values;

        my $sth = $dbh->prepare("INSERT $av_table SET category = ?, authorised_value = ?");
        if (@qualif_authorised_values) {
            $dbh->do("DELETE FROM $av_table WHERE category = 'qualif'");
            foreach my $authorised_value (@qualif_authorised_values) {
                $sth->execute('qualif', $authorised_value);
            }
        }
        if (@lang_authorised_values) {
            $dbh->do("DELETE FROM $av_table WHERE category = 'LANG'");
            foreach my $authorised_value (@lang_authorised_values) {
                $sth->execute('LANG', $authorised_value);
            }
        }
        if (@codepeb_authorised_values) {
            $dbh->do("DELETE FROM $av_table WHERE category = 'CODEPEB'");
            foreach my $authorised_value (@codepeb_authorised_values) {
                $sth->execute('CODEPEB', $authorised_value);
            }
        }

        print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABibLibre%3A%3ATransitionBibliographique&method=configure");
        return;
    }

    my $template = $self->get_template({ file => 'configure.tt' });

    my $qualif_authorised_values = $dbh->selectcol_arrayref("SELECT authorised_value FROM $av_table WHERE category = 'qualif'");
    my $lang_authorised_values = $dbh->selectcol_arrayref("SELECT authorised_value FROM $av_table WHERE category = 'LANG'");
    my $codepeb_authorised_values = $dbh->selectcol_arrayref("SELECT authorised_value FROM $av_table WHERE category = 'CODEPEB'");
    $template->param(
        qualif_authorised_values => $qualif_authorised_values,
        lang_authorised_values => $lang_authorised_values,
        codepeb_authorised_values => $codepeb_authorised_values,
    );

    $self->output_html( $template->output() );
}

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    my $op = $cgi->param('op') // '';
    if ($op eq 'import') {
        return $self->import_action($args);
    } elsif ($op eq 'import_logs') {
        return $self->import_logs_action($args);
    }

    my $template = $self->get_template({ file => 'tmpl/home.tt' });
    return $self->output_html( $template->output() );
}

sub import_action {
    my ($self, $args) = @_;

    my $template = $self->get_template({ file => 'tmpl/import.tt' });

    my $cgi = $self->{cgi};

    if ($cgi->request_method eq 'POST') {
        my @errors = $self->import_validate_form();
        unless (@errors) {
            $self->do_import({
                fh => scalar $cgi->upload('file'),
                file => scalar $cgi->param('file'),
                type => scalar $cgi->param('type'),
                id_column_name => scalar $cgi->param('id_column_name'),
                external_id_column_name => scalar $cgi->param('external_id_column_name'),
                marc_subfield => scalar $cgi->param('marc_subfield'),
                identifier_format => scalar $cgi->param('identifier_format'),
            });

            print $cgi->redirect('/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Com::BibLibre::TransitionBibliographique&method=tool&op=import');
            return;
        }

        $template->param('errors' => \@errors);
    }

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs = $dbh->selectall_arrayref(qq{
        SELECT * FROM $jobs_table
        ORDER BY enqueued_at DESC
        LIMIT 100
    }, { Slice => {} });

    foreach my $job (@$jobs) {
        $job->{args} = decode_json($job->{args});
    }

    $template->param(jobs => $jobs);

    return $self->output_html( $template->output() );
}

sub import_logs_action {
    my ($self, $args) = @_;

    my $template = $self->get_template({ file => 'tmpl/import_logs.tt' });

    my $cgi = $self->{cgi};
    my $job_id = $cgi->param('job_id');
    my $type = $cgi->param('type');

    my $dbh = C4::Context->dbh;
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    my $job_logs = $dbh->selectall_arrayref(qq{
        SELECT * FROM $jobs_logs_table
        WHERE job_id = ?
    } . ($type ? 'AND (type = ? OR type IS NULL)' : '') . qq{
        ORDER BY id ASC
    }, { Slice => {} }, $job_id, $type);

    $template->param(
        job_id => $job_id,
        job_logs => $job_logs,
        type => $type,
    );

    return $self->output_html( $template->output() );
}

sub get_conf {
    my ($self) = @_;

    my $conf_path = $self->mbf_path('config.yaml');
    my $conf = LoadFile($conf_path);

    return $conf;
}

sub do_import {
    my ($self, $args) = @_;

    my $config = $self->get_conf;
    my $upload_path = $config->{import}->{upload_path};

    my $fh = $args->{fh};
    my $file = $args->{file};

    my $filename = time . '_' . $file;
    my $filepath = "$upload_path/$filename";
    open my $out_fh, '>>', $filepath or die "Cannot open $filepath. Check permissions";
    while (my $line = <$fh>) {
        print $out_fh $line;
    }
    close $out_fh;

    my $dbh = C4::Context->dbh;

    my $job_args = {
        type => $args->{type},
        id_column_name => $args->{id_column_name},
        external_id_column_name => $args->{external_id_column_name},
        marc_subfield => $args->{marc_subfield},
        identifier_format => $args->{identifier_format},
        original_filename => "$file", # apparently needs to be converted to string
        filepath => $filepath,
    };

    my $jobs_table = $self->get_qualified_table_name('jobs');
    $dbh->do(qq{
        INSERT INTO $jobs_table (state, args)
        VALUES (?, ?)
    }, undef, 'inactive', encode_json($job_args));
}

sub import_validate_form {
    my ($self) = @_;

    my @errors;
    my $cgi = $self->{cgi};

    my $file = $cgi->param('file');
    if (!$file) {
        push @errors, "Aucun fichier sélectionné";
    }

    my $fh = $cgi->upload('file');
    my $line = <$fh>;
    seek $fh, 0, 0;

    # Try to guess the separator. We know there should be at least 2 columns
    my $sep_char;
    foreach my $separator (',', ';', ':', '|', "\t", ' ') {
        my $csv = Text::CSV::Encoded->new({ sep_char => $separator });
        $csv->parse($line);
        my @columns = $csv->fields();
        if (@columns > 1) {
            $sep_char = $separator;
            last;
        }
    }

    if (defined $sep_char) {
        my $csv = Text::CSV::Encoded->new({ sep_char => $sep_char });
        $csv->parse($line);
        my @columns = $csv->fields();

        my $id_column_name = $cgi->param('id_column_name');
        my $external_id_column_name = $cgi->param('external_id_column_name');
        if (none { $_ eq $id_column_name } @columns) {
            push @errors, "Cette colonne n'existe pas dans le fichier CSV: $id_column_name (colonnes disponibles: [" . join ('], [', @columns) . "])";
        }
        if (none { $_ eq $external_id_column_name } @columns) {
            push @errors, "Cette colonne n'existe pas dans le fichier CSV: $external_id_column_name (colonnes disponibles: " . join (', ', @columns) . ")";
        }
    } else {
        push @errors, "Impossible de deviner le séparateur de colonne. Ce doit être une virgule, un point-virgule, des deux points, une barre verticale (pipe), une tabulation ou un espace. Le CSV doit contenir au moins 2 colonnes";
    }

    my $type = $cgi->param('type');
    my ($tag_structure_source_name, $subfield_structure_source_name);
    if ($type eq 'biblio') {
        $tag_structure_source_name = 'MarcTagStructure';
        $subfield_structure_source_name = 'MarcSubfieldStructure';
    } elsif ($type eq 'authority') {
        $tag_structure_source_name = 'AuthTagStructure';
        $subfield_structure_source_name = 'AuthSubfieldStructure';
    }

    my $marc_subfield = $cgi->param('marc_subfield');
    if ($marc_subfield =~ /^\d{3}\$[a-zA-Z0-9]$/ || $marc_subfield =~ /^00\d$/) {
        my ($tag, $code) = split /\$/, $marc_subfield;
        my $schema = Koha::Database->schema;
        my $tag_rs = $schema->resultset($tag_structure_source_name);
        my $subfield_rs = $schema->resultset($subfield_structure_source_name);

        my $tag_structure = $tag_rs->find('', $tag);
        if (!$tag_structure) {
            push @errors, "Le champ MARC $tag n'existe pas dans la grille de catalogage par défaut";
        }

        if (defined $code) {
            my $subfield_structure = $subfield_rs->find('', $tag, $code);
            if (!$subfield_structure) {
                push @errors, "Le sous-champ MARC $tag\$$code n'existe pas dans la grille de catalogage par défaut";
            }
        }
    } else {
        push @errors, "Le sous-champ MARC doit être au format 'XXX\$y' ou '00X'";
    }

    return @errors;
}

sub job_log {
    my ($self, $job, $message, $type) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    $dbh->do(qq{
        INSERT INTO $jobs_logs_table (job_id, message, type)
        VALUES (?, ?, ?)
    }, undef, $job->{id}, $message, $type);
}

sub execute_jobs {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs = $dbh->selectall_arrayref(qq{
        SELECT * FROM $jobs_table
        WHERE state = 'inactive'
        ORDER BY enqueued_at ASC
    }, { Slice => {} });

    if (@$jobs) {
        foreach my $job (@$jobs) {
            eval {
                say "Executing job " . $job->{id};
                $self->execute_job($job);
            };
            if ($@) {
                say STDERR "Error: " . $@;
                $self->job_log($job, "Erreur pendant le traitement : " . $@, 'error');
                $self->error_job($job);
            }
        }
    } else {
        say "There is no job to execute" if $DEBUG ;
    }
}

sub start_job {
    my ($self, $job) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    $dbh->do(qq{
        UPDATE $jobs_table
        SET started_at = CURRENT_TIMESTAMP, state = 'active'
        WHERE id = ?
    }, undef, $job->{id});

    $self->job_log($job, 'Import démarré');
}

sub finish_job {
    my ($self, $job) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    $dbh->do(qq{
        UPDATE $jobs_table
        SET finished_at = CURRENT_TIMESTAMP, state = 'finished'
        WHERE id = ?
    }, undef, $job->{id});

    $self->job_log($job, 'Import terminé');
}

sub error_job {
    my ($self, $job) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    $dbh->do(qq{
        UPDATE $jobs_table
        SET state = 'error'
        WHERE id = ?
    }, undef, $job->{id});
}

sub execute_job {
    my ($self, $job) = @_;

    my $args = decode_json($job->{args});
    my $type = $args->{type};
    my $filepath = $args->{filepath};
    my $id_column_name = $args->{id_column_name};
    my $external_id_column_name = $args->{external_id_column_name};
    my $marc_subfield = $args->{marc_subfield};
    my $identifier_format = $args->{identifier_format};

    $self->start_job($job);

    open my $fh, '<:encoding(UTF-8)', $filepath or die "Cannot open $filepath: $!";
    my $line = <$fh>;

    # Try to guess the separator. We know there should be at least 2 columns
    my $sep_char;
    foreach my $separator (',', ';', ':', '|', "\t", ' ') {
        my $csv = Text::CSV::Encoded->new({ sep_char => $separator });
        $csv->parse($line);
        my @columns = $csv->fields();
        if (@columns > 1) {
            $sep_char = $separator;
            last;
        }
    }

    unless (defined $sep_char) {
        die "Impossible de deviner le séparateur de colonne. Ce doit être une virgule, un point-virgule, des deux points, une barre verticale (pipe), une tabulation ou un espace. Le CSV doit contenir au moins 2 colonnes";
    }

    my $csv = Text::CSV::Encoded->new({ sep_char => $sep_char });
    $csv->parse($line);
    my @columns = $csv->fields();

    my $id_idx = first_index { $_ eq $id_column_name } @columns;
    if ($id_idx < 0) {
        die "Il n'y a pas de colonne nommée $id_column_name";
    }

    my $external_id_idx = first_index { $_ eq $external_id_column_name } @columns;
    if ($external_id_idx < 0) {
        die "Il n'y a pas de colonne nommée $external_id_column_name";
    }

    my ($tag, $code) = split /\$/, $marc_subfield;

    my ($processed, $updated, $already_uptodate, $notfound) = (0, 0, 0, 0);
    my $linenumber = 1;
    while ($line = <$fh>) {
        $linenumber++;

        $csv->parse($line);
        my @fields = $csv->fields();
        my $id = $fields[$id_idx];
        my $external_ids = $fields[$external_id_idx];

        my @external_ids = split /,/, $external_ids;
        my @arks = grep m|ark:/|, @external_ids;
        if (@arks > 1) {
            $self->job_log($job, "Plusieurs identifiants ARK pour la notice $id (ligne $linenumber)", 'error');
            $processed++;
            next;
        }
        my @ppns = grep m|PPN\d{8}[\dX]|, @external_ids;
        if (@ppns > 1) {
            $self->job_log($job, "Plusieurs identifiants PPN pour la notice $id (ligne $linenumber)", 'error');
            $processed++;
            next;
        }

        if (@external_ids == 0) {
            $self->job_log($job, "Aucun identifiant externe pour la notice $id (ligne $linenumber)", 'error');
            next;
        }

        my $marc_record = $self->get_marc_record($type, $id);
        if ($marc_record) {
            my $was_updated = 0;
            my $was_alreadyuptodate = 0;
            foreach my $external_id (@external_ids) {
                my $clean_identifier = $self->clean_identifier($external_id);
                my @fields = $marc_record->field($tag);
                my $field = grep {
                    any { $self->clean_identifier($_) eq $clean_identifier } (defined $code ? $_->subfield($code) : $_->data());
                } @fields;
                if ($field) {
                    $self->job_log($job, "Identifiant déjà présent pour la notice $id (ligne $linenumber)", 'success');
                    $was_alreadyuptodate = 1;
                } else {
                    my $ark_field = grep {
                        any { $_ =~ m|ark:/| } (defined $code ? $_->subfield($code) : $_->data());
                    } @fields;
                    my $ppn_field = grep {
                        any { $_ =~ m|\d{8}[\dX]| } (defined $code ? $_->subfield($code) : $_->data());
                    } @fields;
                    if ($ark_field && $clean_identifier =~ m|ark:/|) {
                        $self->job_log($job, "Un identifiant ARK différent est déjà présent dans la notice $id (ligne $linenumber)", 'error');
                    } elsif ($ppn_field && $clean_identifier =~ m|\d{8}[\dX]|) {
                        $self->job_log($job, "Un identifiant PPN différent est déjà présent dans la notice $id (ligne $linenumber)", 'error');
                    } else {
                        my $schema = Koha::Database->schema;
                        my $tag_structure_source_name = $type eq 'authority' ? 'AuthTagStructure' : 'MarcTagStructure';
                        my $tag_rs = $schema->resultset($tag_structure_source_name);

                        my $tag_structure = $tag_rs->find('', $tag);
                        if ($tag_structure->repeatable || 0 == (() = $marc_record->field($tag))) {
                            my $formatted_identifier = $self->format_identifier($external_id, $identifier_format, $type);
                            if ($formatted_identifier) {

                                my $new_field = defined $code ?
                                    MARC::Field->new($tag, '', '', $code => $formatted_identifier) :
                                    MARC::Field->new($tag, $formatted_identifier);
                                $marc_record->insert_fields_ordered($new_field);
                                $self->save_marc_record($type, $id, $marc_record);
                                $self->job_log($job, "Identifiant ajouté pour la notice $id (ligne $linenumber)", 'success');
                                $was_updated = 1;
                            } else {
                                $self->job_log($job, "Impossible de formatter l'identifiant, format non reconnu : $external_id", 'error');
                            }
                        } else {
                            $self->job_log($job, "Le champ existe déjà dans la notice $id et n'est pas répétable", 'error');
                        }
                    }
                }
            }
            if ($was_updated) {
                $updated++;
            }
            if ($was_alreadyuptodate) {
                $already_uptodate++;
            }
        } else {
            $self->job_log($job, "Notice $id introuvable (ligne $linenumber)", 'error');
            $notfound++;
        }

        $processed++;
    }

    $self->job_log($job, "Résumé:");
    $self->job_log($job, "    Notices traitées: $processed");
    $self->job_log($job, "    Notices mises à jour: $updated");
    $self->job_log($job, "    Notices non mises à jour: " . ($processed - $updated));
    $self->job_log($job, "    Notices avec identifiant déjà présent: $already_uptodate");
    $self->job_log($job, "    Notices non trouvées: $notfound");

    $self->finish_job($job);
}

sub save_marc_record {
    my ($self, $type, $id, $marc_record) = @_;

    if ($type eq 'biblio') {
        my $frameworkcode = C4::Biblio::GetFrameworkCode($id);
        C4::Biblio::ModBiblio($marc_record, $id, $frameworkcode);
    } elsif ($type eq 'authority') {
        my $authority = Koha::Authorities->find($id);
        my $authtypecode = $authority->authtypecode;
        C4::AuthoritiesMarc::ModAuthority($id, $marc_record, $authtypecode);
    }
}

sub clean_identifier {
    my ($self, $identifier) = @_;

    $identifier =~ s/^\s+//;
    $identifier =~ s/\s+$//;

    if ($identifier =~ /^https?:/) {
        my $uri = URI->new($identifier);
        $identifier = $uri->path;
        $identifier =~ s/^\///;
    }

    $identifier =~ s/^PPN//;

    return $identifier;
}

sub format_identifier {
    my ($self, $identifier, $format, $type) = @_;

    return $identifier unless $format;

    if ($format eq 'clean') {
        return $self->clean_identifier($identifier);
    }

    if ($format eq 'uri') {
        my $clean_identifier = $self->clean_identifier($identifier);
        if ($clean_identifier =~ /^ark:/) {
            return 'https://catalogue.bnf.fr/' . $clean_identifier;
        }
        if ($clean_identifier =~ /^\d{8}[\dX]$/) {
            if ($type eq 'authority') {
                return 'http://www.idref.fr/' . $clean_identifier;
            } else {
                return 'http://www.sudoc.fr/' . $clean_identifier;
            }
        }
    }
}

sub get_marc_record {
    my ($self, $type, $id) = @_;

    my $marc_record;

    if ($type eq 'biblio') {
        my $biblio = Koha::Biblios->find($id);
        $marc_record = $biblio->metadata->record if $biblio;
    } elsif ($type eq 'authority') {
        $marc_record = C4::AuthoritiesMarc::GetAuthority($id);
    }

    return $marc_record;
};

sub purge {
    my ($self, $older_than) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs = $dbh->selectall_arrayref(qq{
        SELECT * FROM $jobs_table
        WHERE state = 'finished'
          AND finished_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)
        ORDER BY enqueued_at ASC
    }, { Slice => {} }, $older_than);

    my $delete_sth = $dbh->prepare(qq{
        DELETE FROM $jobs_table
        WHERE id = ?
    });

    foreach my $job (@$jobs) {
        say "Removing job " . $job->{id};

        $job->{args} = decode_json($job->{args});
        my $filepath = $job->{args}->{filepath};

        say "Removing file $filepath";
        unlink $filepath or say STDERR "Could not unlink file $filepath: $!";

        say "Removing database entry";
        $delete_sth->execute($job->{id}) or say STDERR "Could not remove database entry: " . $delete_sth->errstr;
    }
}

1;

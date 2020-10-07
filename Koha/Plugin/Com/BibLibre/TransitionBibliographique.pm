package Koha::Plugin::Com::BibLibre::TransitionBibliographique;

use base qw(Koha::Plugins::Base);

use Modern::Perl;
use utf8;

use Encode;
use JSON;
use List::MoreUtils qw(first_index any none);
use Text::CSV::Encoded;
use YAML qw(LoadFile);

use C4::AuthoritiesMarc;
use C4::Biblio;
use C4::Context;

use Koha::Authorities;
use Koha::Authority;
use Koha::Database;

our $VERSION = "0.2.0";

our $metadata = {
    name            => 'Transition bibliographique',
    author          => 'BibLibre',
    date_authored   => '2019-03-25',
    date_updated    => "2019-03-25",
    minimum_version => '18.1100000',
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

    my $jobs_table = $self->get_qualified_table_name('jobs');
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    $dbh->do(qq{
        DROP TABLE IF EXISTS $jobs_logs_table
    });
    $dbh->do(qq{
        DROP TABLE IF EXISTS $jobs_table
    });

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
    if ($marc_subfield =~ /^\d{3}\$[a-zA-Z0-9]$/) {
        my ($tag, $code) = split /\$/, $marc_subfield;
        my $schema = Koha::Database->schema;
        my $tag_rs = $schema->resultset($tag_structure_source_name);
        my $subfield_rs = $schema->resultset($subfield_structure_source_name);

        my $tag_structure = $tag_rs->find('', $tag);
        if ($tag_structure) {
            if (!$tag_structure->repeatable) {
                push @errors, "Le champ MARC $tag n'est pas répétable";
            }
        } else {
            push @errors, "Le champ MARC $tag n'existe pas dans la grille de catalogage par défaut";
        }

        my $subfield_structure = $subfield_rs->find('', $tag, $code);
        if (!$subfield_structure) {
            push @errors, "Le sous-champ MARC $tag\$$code n'existe pas dans la grille de catalogage par défaut";
        }
    } else {
        push @errors, "Le sous-champ MARC doit être au format 'XXX\$y'";
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
                    any { $self->clean_identifier($_) eq $clean_identifier } $_->subfield($code);
                } @fields;
                if ($field) {
                    $self->job_log($job, "Identifiant déjà présent pour la notice $id (ligne $linenumber)", 'success');
                    $was_alreadyuptodate = 1;
                } else {
                    my $ark_field = grep {
                        any { $_ =~ m|ark:/| } $_->subfield($code);
                    } @fields;
                    my $ppn_field = grep {
                        any { $_ =~ m|\d{8}[\dX]| } $_->subfield($code);
                    } @fields;
                    if ($ark_field && $clean_identifier =~ m|ark:/|) {
                        $self->job_log($job, "Un identifiant ARK différent est déjà présent dans la notice $id (ligne $linenumber)", 'error');
                    } elsif ($ppn_field && $clean_identifier =~ m|\d{8}[\dX]|) {
                        $self->job_log($job, "Un identifiant PPN différent est déjà présent dans la notice $id (ligne $linenumber)", 'error');
                    } else {
                        my $formatted_identifier = $self->format_identifier($external_id, $identifier_format, $type);
                        if ($formatted_identifier) {
                            $marc_record->insert_fields_ordered(
                                MARC::Field->new($tag, '', '', $code => $formatted_identifier),
                            );
                            $self->save_marc_record($type, $id, $marc_record);
                            $self->job_log($job, "Identifiant ajouté pour la notice $id (ligne $linenumber)", 'success');
                            $was_updated = 1;
                        } else {
                            $self->job_log($job, "Impossible de formatter l'identifiant, format non reconnu : $external_id", 'error');
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
        $marc_record = C4::Biblio::GetMarcBiblio({ biblionumber => $id });
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

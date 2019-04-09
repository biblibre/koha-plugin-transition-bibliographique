package Koha::Plugin::Com::BibLibre::TransitionBibliographique;

use base qw(Koha::Plugins::Base);

use Modern::Perl;

use Catmandu;
use Catmandu::Exporter::MARC;
use Catmandu::Sane;
use Encode;
use File::Temp qw(tempfile);
use JSON;
use List::MoreUtils qw(first_index any);
use Text::CSV::Encoded;
use YAML qw(LoadFile);

use C4::AuthoritiesMarc;
use C4::Biblio;
use C4::Context;

use Koha::Authorities;
use Koha::Authority;
use Koha::Database;

our $VERSION = "0.1.0";

our $metadata = {
    name            => 'Transition bibliographique',
    author          => 'BibLibre',
    date_authored   => '2019-03-25',
    date_updated    => "2019-03-25",
    minimum_version => '18.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin aims to ease data export with catmandu and data import into catalogue (biblios and authorities)',
};

our %content_type_mapping = (
    CSV => 'text/csv',
    TSV => 'text/csv',
    JSON => 'application/json',
    MARC => 'application/marc',
);

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

    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    $dbh->do(qq{
        DROP TABLE IF EXISTS $jobs_logs_table
    });
    $dbh->do(qq{
        CREATE TABLE $jobs_logs_table (
            id SERIAL,
            job_id BIGINT UNSIGNED NOT NULL,
            logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
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
    if ($op eq 'export') {
        return $self->export($args);
    } elsif ($op eq 'import') {
        return $self->import_action($args);
    } elsif ($op eq 'import_logs') {
        return $self->import_logs_action($args);
    }

    my $template = $self->get_template({ file => 'tmpl/home.tt' });
    return $self->output_html( $template->output() );
}

sub export {
    my ($self, $args) = @_;

    my $template = $self->get_template({ file => 'tmpl/export.tt' });

    my $cgi = $self->{cgi};

    if ($cgi->request_method eq 'POST') {
        my @errors = $self->validate_form();
        unless (@errors) {
            return $self->do_export({
                fix => scalar $cgi->param('fix'),
                file => scalar $cgi->param('file'),
                format => scalar $cgi->param('format'),
                filename => scalar $cgi->param('filename'),
            });
        }

        $template->param('errors' => \@errors);
    }

    my $conf = $self->get_conf;
    my $export_path = $conf->{export}->{path};

    my @files;
    opendir(my $dh, $export_path);
    while (my $file = decode_utf8(readdir $dh)) {
        push @files, $file unless $file =~ /^\./;
    }
    closedir $dh;
    @files = sort @files;

    my @fixes;
    my $fixes_path = $self->mbf_path('fixes');
    opendir $dh, $fixes_path;
    while (my $fix = decode_utf8(readdir $dh)) {
        next if $fix =~ /^\./;

        my $title = $fix;

        open my $fh, '<:encoding(UTF-8)', "$fixes_path/$fix";
        my $fix_content = '';
        while (<$fh>) {
            if (/^# title: (.*)$/) {
                $title = $1;
            }
            $fix_content .= $_;
        }

        push @fixes, {
            name => $fix,
            title => $title,
            content => $fix_content,
        };
    }
    @fixes = sort { $a->{title} cmp $b->{title} } @fixes;

    $template->param(
        files => \@files,
        fixes => \@fixes,
    );

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
            });
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

    my $dbh = C4::Context->dbh;
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    my $job_logs = $dbh->selectall_arrayref(qq{
        SELECT * FROM $jobs_logs_table
        WHERE job_id = ?
        ORDER BY logged_at ASC
    }, { Slice => {} }, $job_id);

    $template->param(
        job_id => $job_id,
        job_logs => $job_logs,
    );

    return $self->output_html( $template->output() );
}

sub check_fix_content {
    my ($self, $fix_content) = @_;

    my $parser = Catmandu::Fix::Parser->new;
    try {
        my $fixes = $parser->parse($fix_content);
        my @errors = $self->check_fixes($fixes);
        if (@errors) {
            return @errors;
        }

        return;
    } catch {
        return "Catmandu fix parser error: " . $_->message;
    };
}

sub check_fixes {
    my ($self, $fixes) = @_;

    my @errors;
    foreach my $fix (@$fixes) {
        if ($fix->DOES('Catmandu::Fix::Condition')) {
            push @errors, $self->check_fixes($fix->pass_fixes);
            push @errors, $self->check_fixes($fix->fail_fixes);
        } elsif ($fix->DOES('Catmandu::Fix::Bind')) {
            push @errors, $self->check_fixes($fix->__fixes__);
        } else {
            if ($fix->isa('Catmandu::Fix::perlcode')) {
                push @errors, 'perlcode fix is not allowed',
            } elsif ($fix->isa('Catmandu::Fix::cmd')) {
                push @errors, 'cmd fix is not allowed';
            }
        }
    }

    return @errors;
}

sub get_conf {
    my ($self) = @_;

    my $conf_path = $self->mbf_path('config.yaml');
    my $conf = LoadFile($conf_path);

    return $conf;
}

sub get_fixpath {
    my ($self) = @_;

    my $fix = $self->{cgi}->param('fix');
    my $fix_content = $self->{cgi}->param('fix-content');

    my $fixpath = $self->mbf_path("fixes/$fix");
    if ($fix_content) {
        my ($fh, $tempfilename) = tempfile();
        print $fh $fix_content;
        close $fh;
        $fixpath = $tempfilename;
    }

    return $fixpath;
}

sub do_export {
    my ($self, $args) = @_;

    my $config = $self->get_conf;
    my $export_path = $config->{export}->{path};

    my $fix = $args->{fix};
    my $file = $args->{file};
    my $filepath = "$export_path/$file";

    my $fixpath = $self->get_fixpath();

    my $format = $args->{format};

    my $importer = Catmandu->importer('MARC', file => $filepath);
    my $fixer = Catmandu->fixer($fixpath);
    my $exporter = Catmandu->exporter($format);

    my $default_filename = 'export.' . lc($format);
    my $filename = $args->{filename} || $default_filename;

    print $self->{cgi}->header(
        -type => $content_type_mapping{$format},
        -content_disposition => "attachment; filename=$filename",
    );
    $exporter->add_many($fixer->fix($importer));
    $exporter->commit;
}

sub validate_form {
    my ($self) = @_;

    my @errors;

    my $cgi = $self->{cgi};
    my $fix_content = $cgi->param('fix-content');
    if ($fix_content) {
        @errors = $self->check_fix_content($fix_content);
    }

    return @errors;
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
        push @errors, "No file selected";
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
                push @errors, "MARC field $tag is not repeatable";
            }
        } else {
            push @errors, "MARC field $tag does not exist in default framework";
        }

        my $subfield_structure = $subfield_rs->find('', $tag, $code);
        if (!$subfield_structure) {
            push @errors, "MARC subfield $tag\$$code does not exist in default framework";
        }
    } else {
        push @errors, "MARC subfield should be in the format 'XXX\$y'";
    }

    return @errors;
}

sub job_log {
    my ($self, $job, $message) = @_;

    my $dbh = C4::Context->dbh;
    my $jobs_logs_table = $self->get_qualified_table_name('jobs_logs');
    $dbh->do(qq{
        INSERT INTO $jobs_logs_table (job_id, message)
        VALUES (?, ?)
    }, undef, $job->{id}, $message);
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
                $self->execute_job($job);
            };
            if ($@) {
                $self->job_log($job, 'Error while executing job : ' . $@);
                $self->error_job($job);
            }
        }
    } else {
        say STDERR "There is no job to execute";
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

    $self->job_log($job, 'Started import');
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

    $self->job_log($job, 'Finished import');
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

    $self->start_job($job);

    open my $fh, '<:encoding(UTF-8)', $filepath or die "Cannot open $filepath: $!";
    my $csv = Text::CSV::Encoded->new({ encoding => 'utf8' });
    my $line = <$fh>;
    $csv->parse($line);
    my @columns = $csv->fields();

    my $id_idx = first_index { $_ eq $id_column_name } @columns;
    if ($id_idx < 0) {
        die "There is no column named $id_column_name";
    }

    my $external_id_idx = first_index { $_ eq $external_id_column_name } @columns;
    if ($external_id_idx < 0) {
    die "There is no column named $external_id_column_name";
    }

    my ($tag, $code) = split /\$/, $marc_subfield;

    my $linenumber = 1;
    while ($line = <$fh>) {
        $linenumber++;

        $csv->parse($line);
        my @fields = $csv->fields();
        my $id = $fields[$id_idx];
        my $external_id = $fields[$external_id_idx];

        my $clean_identifier = $self->clean_identifier($external_id);
        my $marc_record = $self->get_marc_record($type, $id);
        if ($marc_record) {
            my @fields = $marc_record->field($tag);
            my $field = grep {
                any { $self->clean_identifier($_) eq $clean_identifier } $_->subfield($code);
            } @fields;
            if ($field) {
                $self->job_log($job, "Identifier already present for id $id (line $linenumber)");
            } else {
                $marc_record->insert_fields_ordered(
                    MARC::Field->new($tag, '', '', $code => $external_id),
                );
                $self->save_marc_record($type, $id, $marc_record);
                $self->job_log($job, "Identifier added for id $id (line $linenumber)");
            }
        } else {
            $self->job_log($job, "Record not found for id $id (line $linenumber)");
        }
    }

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

    if ($identifier =~ /^http:/) {
        my $uri = URI->new($identifier);
        $identifier = $uri->path;
        $identifier =~ s/^\///;
    }

    $identifier =~ s/^PPN//;

    return $identifier;
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

1;

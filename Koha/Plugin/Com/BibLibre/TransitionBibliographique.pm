package Koha::Plugin::Com::BibLibre::TransitionBibliographique;

use base qw(Koha::Plugins::Base);

use Modern::Perl;

use Catmandu;
use Catmandu::Exporter::MARC;
use Catmandu::Sane;
use Encode;
use File::Temp qw(tempfile);
use YAML qw(LoadFile);

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

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    my $op = $cgi->param('op');
    if ($op eq 'export') {
        return $self->export($args);
    } elsif ($op eq 'import') {
        return $self->import($args);
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

1;

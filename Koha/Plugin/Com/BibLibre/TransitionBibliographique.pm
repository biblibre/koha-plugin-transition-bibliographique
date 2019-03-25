package Koha::Plugin::Com::BibLibre::TransitionBibliographique;

use base qw(Koha::Plugins::Base);

use Encode;
use File::Slurp qw(read_file);
use YAML qw(LoadFile);

our $VERSION = "0.1.0";

## Here is our metadata, some keys are required, some are optional
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

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    my $op = $cgi->param('op');
    my $template;
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

    $conf = $self->get_conf;

    my $export_path = $conf->{export}->{path};
    my @files;
    opendir my $dh, $export_path;
    while (my $file = decode_utf8(readdir $dh)) {
        push @files, $file unless $file =~ /^\./;
    }
    closedir $dh;

    my @fixes;
    my $fixes_path = $self->mbf_path('fixes');
    opendir $dh, $fixes_path;
    while (my $fix = decode_utf8(readdir $dh)) {
        next if $fix =~ /^\./;

        my $fix_content = read_file("$fixes_path/$fix", binmode => ':utf8');
        my $title = $fix;
        if ($fix_content =~ /^# title: (.*)$/m) {
            $title = $1;
        }

        push @fixes, {
            name => $title,
            content => $fix_content,
        };
    }

    $template->param(
        files => \@files,
        fixes => \@fixes,
    );

    return $self->output_html( $template->output() );
}

sub get_conf {
    my ($self) = @_;

    my $conf_path = $self->mbf_path('config.yaml');
    my $conf = LoadFile($conf_path);

    return $conf;
}

1;

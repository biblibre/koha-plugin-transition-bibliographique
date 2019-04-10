#!/usr/bin/perl

use Modern::Perl;
use Getopt::Long;

use Koha::Plugins;

use Koha::Plugin::Com::BibLibre::TransitionBibliographique;

my $help;
my $older_than = 30;

GetOptions(
    'help' => \$help,
    'older-than=i' => \$older_than,
) or die usage();

if ($help) {
    print usage();
    exit;
}

my $plugin = Koha::Plugin::Com::BibLibre::TransitionBibliographique->new({
    enable_plugins => 1,
});
$plugin->purge($older_than);

sub usage {
    my $usage = <<'EOF';
purge.pl [options]
purge.pl --help

Remove finished jobs and related files

Options
    --older-than=DAYS
        Remove jobs that are finished since more than DAYS days ago.
        Defaults to 30

    --help
        Display this help message
EOF

    return $usage;
}

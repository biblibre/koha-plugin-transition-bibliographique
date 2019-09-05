#!/usr/bin/perl

use Modern::Perl;

use Fcntl ':flock';

use C4::Context;
use Koha::Plugins;

use Koha::Plugin::Com::BibLibre::TransitionBibliographique;

# Prevent two instances running at the same time
open my $fh, '<', $0 or die "Cannot open $0 : $!";
unless (flock $fh, LOCK_EX | LOCK_NB) {
    say STDERR "job-runner is already running";
    exit;
}

my $plugin = Koha::Plugin::Com::BibLibre::TransitionBibliographique->new({
    enable_plugins => 1,
});
$plugin->execute_jobs();

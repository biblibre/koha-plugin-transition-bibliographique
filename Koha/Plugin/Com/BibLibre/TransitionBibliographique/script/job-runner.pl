#!/usr/bin/perl

use Modern::Perl;

use C4::Context;
use Koha::Plugins;

use Koha::Plugin::Com::BibLibre::TransitionBibliographique;

my $plugin = Koha::Plugin::Com::BibLibre::TransitionBibliographique->new({
    enable_plugins => 1,
});
$plugin->execute_jobs();

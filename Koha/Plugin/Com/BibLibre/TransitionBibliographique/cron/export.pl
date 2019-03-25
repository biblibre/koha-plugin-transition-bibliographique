#!/usr/bin/env perl

use utf8;

use Modern::Perl;
use C4::Context;

use Koha::Plugins;
use Koha::Exporter::Record;
use Koha::Plugin::Com::BibLibre::TransitionBibliographique;

my $intranetdir = C4::Context->config('intranetdir');
my $export_script = "$intranetdir/misc/export_records.pl";

my $tb = Koha::Plugin::Com::BibLibre::TransitionBibliographique->new;
my $config = $tb->get_conf;
my $export_path = $config->{export}->{path};

my $dbh = C4::Context->dbh;
my $biblionumbers = $dbh->selectcol_arrayref(q{
    SELECT biblionumber FROM biblio
});
my $authids = $dbh->selectcol_arrayref(q{
    SELECT authid FROM auth_header
});

Koha::Exporter::Record::export({
    record_type => 'bibs',
    record_ids => $biblionumbers,
    format => 'iso2709',
    export_items => 1,
    output_filepath => "$export_path/Catalogue complet biblios avec exemplaires.mrc",
});
Koha::Exporter::Record::export({
    record_type => 'bibs',
    record_ids => $biblionumbers,
    format => 'iso2709',
    export_items => 0,
    output_filepath => "$export_path/Catalogue complet biblios.mrc",
});
Koha::Exporter::Record::export({
    record_type => 'auths',
    record_ids => $authids,
    format => 'iso2709',
    output_filepath => "$export_path/Catalogue complet autorités.mrc",
});

$biblionumbers = $dbh->selectcol_arrayref(q{
    SELECT biblionumber FROM biblio LIMIT 10000
});
$authids = $dbh->selectcol_arrayref(q{
    SELECT authid FROM auth_header LIMIT 10000
});
Koha::Exporter::Record::export({
    record_type => 'bibs',
    record_ids => $biblionumbers,
    format => 'iso2709',
    export_items => 1,
    output_filepath => "$export_path/Jeu de test (10000 biblios avec exemplaires).mrc",
});
Koha::Exporter::Record::export({
    record_type => 'auths',
    record_ids => $authids,
    format => 'iso2709',
    output_filepath => "$export_path/Jeu de test (10000 autorités).mrc",
});

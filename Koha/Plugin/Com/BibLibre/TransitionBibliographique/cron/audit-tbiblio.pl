#!/usr/bin/env perl

use utf8;

use Modern::Perl;
use C4::Context;
use autouse 'Data::Dumper' => qw(Dumper);

use Koha::Plugins;
use Koha::Exporter::Record;
use Koha::Plugin::Com::BibLibre::TransitionBibliographique;



sub check_for_audit {

  say "Date : ". &_get_date;

  say "\nGrille de catalogage default";
  &_get_marcframework_validation;


  say "\nCount records";
  say &_get_count_records_with_fields;
}

sub _get_date {
  use POSIX qw(strftime);
  my $date = strftime "%m/%d/%Y", localtime;
}

sub _get_marcframework_validation {
    my $marcstructure = C4::Biblio::GetMarcStructure(1,'');

    my $ok = "\033[32;1mv\033[0m" ;
    my $ko = "\033[31;1mx\033[0m";

    say "009:" . (defined($marcstructure->{'009'}) ? $ok : $ko);
    say "033a:" . (defined($marcstructure->{'033'}->{'a'}) ? $ok : $ko);
    say "181c:" . (defined($marcstructure->{'181'}->{'c'}) ? $ok : $ko);
    say "182c:" . (defined($marcstructure->{'182'}->{'c'}) ? $ok : $ko);
    say "183c:" . (defined($marcstructure->{'183'}->{'c'}) ? $ok : $ko);
    say "219:" . (defined($marcstructure->{'219'}) ? $ok : $ko);

}

#15:19 <jajm> et pour "requêter la base pour compter le nombre de notice avec tel ou telle valeur", le mieux c'est d'utiliser extractvalue à mon avis
sub _get_count_records_with_fields {
  #"SELECT biblionumber, ExtractValue(metadata,'count(//datafield[@tag="033"])') AS count033 FROM biblio_metadata HAVING count033 > 1|;"

  my $dbh = C4::Context->dbh;
  my $count_sth = $dbh->prepare(
      q|
      SELECT biblionumber, ExtractValue(metadata,'count(//datafield[@tag="033"])') AS count033 FROM biblio_metadata HAVING count033 > 1
      |
  );
#  my $count_sth = $dbh->prepare(
#      q|
#      SELECT COUNT(biblionumber)
#      FROM biblio_metadata
#      WHERE format='marcxml'
#          AND (
#              ExtractValue(metadata,'//datafield[@tag="033"]/subfield[@code="a"]')
#              )
#      |
#  );17:16 <jajm> il manque quelque chose à ta condition, AND ExtractValue(...) [ != '' ? ]

  $count_sth->execute( C4::Context->preference('marcflavour') );
  my ( $num_records ) = $count_sth->fetchrow;
}

&check_for_audit;

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
  say &_query_database_for_count(&_get_count_biblios);

  say "\nCount records with fields";
  say &_get_count_records_with_fields;

  say "\nCount BnF ARK";
  say &_query_database_for_count(&_get_count_ark_bnf);

  say "\nCount PPN";
  say &_query_database_for_count(&_get_count_ppn_id);

  say "\nCount Others 033a";
  say &_query_database_for_count(&_get_count_others_033a);

  say "\nCount aligned Biblios";
  say &_query_database_for_count(&_get_count_aligned_biblios);

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

sub _query_database_for_count {
  my (  $query ) = @_;
  my $dbh = C4::Context->dbh;
  my $count_sth = $dbh->prepare($query);
  $count_sth->execute();
  my ( $num_records ) = $count_sth->fetchrow;
}

sub _get_count_biblios {
  my $query = q|
          select count(*) from biblio;
        |;
}

sub _get_count_ark_bnf {
  # count O33a contenant ark:/12148/
  my $query = q|
  select count(*) as count from biblio_metadata
  where ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "%ark:/12148/%";
  |;
}

sub _get_count_ppn_id {
  # count 009 ou O33a contient PPN* ou sudoc.fr/* ou 009=[alphanum]
  my $query = q|
  select count(*) as count from biblio_metadata
  where
    (ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "%sudoc.fr/%"
      OR
    ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "PPN%"
      OR
    ExtractValue(metadata, '//controlfield[@tag="009"]') like "PPN%"
      OR
    ExtractValue(metadata, '//controlfield[@tag="009"]') like "%sudoc.fr/%"
      OR
    ExtractValue(metadata, '//controlfield[@tag="009"]') REGEXP '^[A-Za-z0-9]+$')
    ;
  |;
}

sub _get_count_others_033a {
  # count O33a qui n'ont ni ark ni ppn et les notices avec une valeur en 033a
  my $query = q|
      select count(*) as count from biblio_metadata
      where
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') not like "%sudoc.fr/%"
          AND
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') not like "PPN%"
          AND
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') not like "%ark:/12148/%"
          AND
        ExtractValue(metadata, 'count(//datafield[@tag="033"]/subfield[@code="a"])') > 0
    ;
  |;
}

sub _get_count_aligned_biblios {
  # count O33a contient un seul %ark:/12148/% ou un ark et un PPN ou un PPN
  # (notice "alignée de manière unique avec un réservoir national")
  # where  la combinatoire des clauses précédentes
  # (count = 1 et like ark) ou (count = 1 et (like sudoc.com ou like ppn)) ou (count=2 et like ark et (like sudoc.com ou like ppn))
  my $query = q|
      select count(*) as count from biblio_metadata
      where
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "%sudoc.fr/%"
          OR
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "PPN%"
          OR
        ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "%ark:/12148/%"
    ;
  |;
}

sub _get_count_records_with_fields {

  my $marc_ref = {
    '033a' => {
      field => '033',
      subfield => 'a',
      count => undef
    },
    '181c' => {
      field => '181',
      subfield => 'c',
      count => undef
    },
    '182c' => {
      field => '182',
      subfield => 'c',
      count => undef
    },
    '183c' => {
      field => '183',
      subfield => 'c',
      count => undef
    },
    '009' => {
      field => '009',
      subfield => undef,
      count => undef
    },
    '219' => {
      field => '219',
      subfield => undef,
      count => undef
    }
  };

  my $dbh = C4::Context->dbh;
  my $query;

  foreach my $value (keys %$marc_ref) {

    if (defined $marc_ref->{$value}->{"subfield"}) {
      $query = q|
          select count(*) as count from biblio_metadata
          where ExtractValue(metadata, 'count(//datafield[@tag="#field#"]/subfield[@code="#subfield#"])')>0;
        |;
    } else {
      $query = q|
          select count(*) as count from biblio_metadata
          where ExtractValue(metadata, 'count(//controlfield[@tag="#field#"])')>0;
        |;
    }

    my $query_to_run = $query =~ s/#field#/$marc_ref->{$value}->{"field"}/r;
    $query_to_run = $query_to_run =~ s/#subfield#/$marc_ref->{$value}->{"subfield"}/r;

    #print "querytorun:".$query_to_run;

    my $count_sth = $dbh->prepare($query_to_run);
    $count_sth->execute(  );
    my ( $num_records ) = $count_sth->fetchrow;

    print "$value : ".$num_records."\n";
    $marc_ref->{$value}->{"count"} = $num_records;
  }

  #warn Dumper $marc_ref;

}

&check_for_audit;

#/usr/bin/env perl

use Modern::Perl;
use C4::Context;

use Koha::Plugins;
use Koha::Exporter::Record;
use Koha::Plugin::Com::BibLibre::TransitionBibliographique;

my $table = "koha_plugin_com_biblibre_transitionbibliographique_audit_tb";

sub check_for_audit {
  my %result;
  say "Date : ". _get_date();

  say "\nCount records";
  %result = _query_database_for_count_and_save(_get_count_biblios(), "count_biblios");
  say $result{num_records};

  say "\nDefault Marc framework";
  %result = _get_marcframework_validation ($result{id});

  say "\nCount records with fields";
  %result = _get_count_records_with_fields ($result{id});

  say "\nCount BnF ARK";
  %result =  _query_database_for_count_and_save(_get_count_ark_bnf(), "count_bnf_ark", $result{id});
  say $result{num_records};

  say "\nCount PPN";
  %result = _query_database_for_count_and_save(_get_count_ppn_id(), "count_sudoc_ppn", $result{id});
  say $result{num_records};

  say "\nCount Others 033a";
  %result = _query_database_for_count_and_save(_get_count_others_033a(), "count_ids_in_033a", $result{id});
  say $result{num_records};

  say "\nCount aligned Biblios";
  %result = _query_database_for_count_and_save(_get_count_aligned_biblios(), "count_aligned_biblios", $result{id});
  say $result{num_records};

}

sub _get_date {
  use POSIX qw(strftime);
  return strftime "%m/%d/%Y", localtime;
}

sub _get_marcframework_validation {
    my ( $id ) = @_;
    my %returns;

    my $marcstructure = C4::Biblio::GetMarcStructure(1,'');

    my $ok = "\033[32;1mv\033[0m" ;
    my $ko = "\033[31;1mx\033[0m";

    my $check_marcfield_009  = $marcstructure->{'009'};
    my $check_marcfield_033a = $marcstructure->{'010'}->{'a'};
    my $check_marcfield_033a = $marcstructure->{'011'}->{'a'};
    my $check_marcfield_033a = $marcstructure->{'033'}->{'a'};
    my $check_marcfield_033a = $marcstructure->{'073'}->{'a'};
    my $check_marcfield_181c = $marcstructure->{'181'}->{'c'};
    my $check_marcfield_182c = $marcstructure->{'182'}->{'c'};
    my $check_marcfield_183c = $marcstructure->{'183'}->{'c'};
    my $check_marcfield_214  = $marcstructure->{'214'};
    my $check_marcfield_219  = $marcstructure->{'219'};

    say "009:"  .  (defined($check_marcfield_009) ? $ok : $ko);
    say "010a:" . (defined($check_marcfield_010a) ? $ok : $ko);
    say "011a:" . (defined($check_marcfield_011a) ? $ok : $ko);
    say "033a:" . (defined($check_marcfield_033a) ? $ok : $ko);
    say "073a:" . (defined($check_marcfield_073a) ? $ok : $ko);
    say "181c:" . (defined($check_marcfield_181c) ? $ok : $ko);
    say "182c:" . (defined($check_marcfield_182c) ? $ok : $ko);
    say "183c:" . (defined($check_marcfield_183c) ? $ok : $ko);
    say "214:"  .  (defined($check_marcfield_214) ? $ok : $ko);
    say "219:"  .  (defined($check_marcfield_219) ? $ok : $ko);

    %returns = _save_data (undef, "check_marcfield_009",  (defined($check_marcfield_009))  , $id);
    %returns = _save_data (undef, "check_marcfield_010a", (defined($check_marcfield_010a)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_011a", (defined($check_marcfield_011a)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_033a", (defined($check_marcfield_033a)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_073a", (defined($check_marcfield_073a)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_181c", (defined($check_marcfield_181c)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_182c", (defined($check_marcfield_182c)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_183c", (defined($check_marcfield_183c)) , $returns{id});
    %returns = _save_data (undef, "check_marcfield_214",  (defined($check_marcfield_214))  , $returns{id});
    %returns = _save_data (undef, "check_marcfield_219",  (defined($check_marcfield_219))  , $returns{id});

    return %returns;
}

sub _save_data {
  my ( $dbh, $field, $value, $id ) = @_;
  my %returns;

  $dbh = C4::Context->dbh;
  if (defined $id) {
    $dbh->do( "UPDATE $table SET $field = '$value' WHERE audit_id= '$id'" );
    $returns{id} = $id;
  } else {
    $dbh->do( "INSERT INTO $table ( $field ) VALUES ( ? )", undef, ($value) );
    $returns{id} = $dbh->last_insert_id( undef, undef, $table, undef );
  }
  return %returns;

}

sub _query_database_for_count_and_save {
  my ( $query, $field, $id ) = @_;
  #say "BEFORE".$id;
  my %returns;
  my $dbh = C4::Context->dbh;
  my $count_sth = $dbh->prepare($query);
  $count_sth->execute();
  $returns{num_records} = $count_sth->fetchrow;
  if (defined $id) {
    $dbh->do( "UPDATE $table SET $field = '$returns{num_records}' WHERE audit_id= '$id' ");
    $returns{id} = $id;

  } else {
    $dbh->do( "INSERT INTO $table ( $field ) VALUES ( ? )", undef, ($returns{num_records}) );
    $returns{id} = $dbh->last_insert_id( undef, undef, $table, undef );
  }
  #say "AFTER".$returns{id};

  return %returns;
}

sub _get_count_biblios {
  return q|
          select count(*) from biblio;
        |;
}

sub _get_count_ark_bnf {
  # count O33a contenant ark:/12148/
  return q|
  select count(*) as count from biblio_metadata
  where ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') like "%ark:/12148/%";
  |;
}

sub _get_count_ppn_id {
  # count 009 ou O33a contient PPN* ou sudoc.fr/* ou 009=[alphanum]
  return q|
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
  return q|
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
  return q|
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
  my ( $id ) = @_;
  my %returns;

  my $marc_ref = {
    '010a' => {
      field => '010',
      subfield => 'a',
      count => undef,
      column => 'count_marcfield_010a'
    },
    '011a' => {
      field => '011',
      subfield => 'a',
      count => undef,
      column => 'count_marcfield_011a'
    },
    '033a' => {
      field => '033',
      subfield => 'a',
      count => undef,
      column => 'count_marcfield_033a'
    },
    '073a' => {
      field => '073',
      subfield => 'a',
      count => undef,
      column => 'count_marcfield_073a'
    },
    '181c' => {
      field => '181',
      subfield => 'c',
      count => undef,
      column => 'count_marcfield_181c'
    },
    '182c' => {
      field => '182',
      subfield => 'c',
      count => undef,
      column => 'count_marcfield_182c'
    },
    '183c' => {
      field => '183',
      subfield => 'c',
      count => undef,
      column => 'count_marcfield_183c'
    },
    '009' => {
      field => '009',
      subfield => undef,
      count => undef,
      column => 'count_marcfield_009'
    },
    '214' => {
      field => '214',
      subfield => undef,
      count => undef,
      column => 'count_marcfield_214'
    },
    '219' => {
      field => '219',
      subfield => undef,
      count => undef,
      column => 'count_marcfield_219'
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
  if (defined $id) {
    $returns{id} = $id;
  }
  foreach my $value (keys %$marc_ref) {
    %returns = _save_data (
      $dbh,
      $marc_ref->{$value}->{"column"},
      $marc_ref->{$value}->{"count"},
      $returns{id}
    );

  }
  return %returns;

}

check_for_audit();

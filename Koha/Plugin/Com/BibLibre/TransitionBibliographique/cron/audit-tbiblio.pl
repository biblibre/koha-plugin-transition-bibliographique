#!/usr/bin/env perl

use Modern::Perl;
use utf8;
use open ':std', ':encoding(UTF-8)';

use Array::Utils qw(array_minus intersect);
use DateTime;
use Getopt::Long qw(:config gnu_getopt no_auto_abbrev no_ignore_case);

use C4::Biblio;
use Koha::Database;

my %opts;
GetOptions(
    \%opts,
    'dry-run|n',
    'help|h',
) or die "Error in command line arguments\n";

if ($opts{help}) {
    say <<EOT;
Usage: audit-tbiblio.pl [options...]

Options:
    -h, --help
        Print this help message and exit

    -n, --dry-run
        Do not save anything in database
EOT
    exit;
}

my $dbh = Koha::Database->dbh;

sub green { sprintf("\033[32;1m%s\033[0m", shift) }
sub red { sprintf("\033[31;1m%s\033[0m", shift) }

say "Date : " . DateTime->now->ymd;

my %audit;

say "\nCount records";
($audit{count_biblios}) = $dbh->selectrow_array('SELECT COUNT(*) FROM biblio');
say $audit{count_biblios};

say "\nDefault Marc framework";

my $marcstructure = C4::Biblio::GetMarcStructure(1,'');

my $ok = green('✓');
my $ko = red('✗ missing');

$audit{check_marcfield_009}  = defined $marcstructure->{'009'};
$audit{check_marcfield_010a} = defined $marcstructure->{'010'}->{'a'};
$audit{check_marcfield_011a} = defined $marcstructure->{'011'}->{'a'};
$audit{check_marcfield_029}  = defined $marcstructure->{'029'};
$audit{check_marcfield_033a} = defined $marcstructure->{'033'}->{'a'};
$audit{check_marcfield_073a} = defined $marcstructure->{'073'}->{'a'};
$audit{check_marcfield_1012} = defined $marcstructure->{'101'}->{'2'};
$audit{check_marcfield_181c} = defined $marcstructure->{'181'}->{'c'};
$audit{check_marcfield_182c} = defined $marcstructure->{'182'}->{'c'};
$audit{check_marcfield_183c} = defined $marcstructure->{'183'}->{'c'};
$audit{check_marcfield_214}  = defined $marcstructure->{'214'};
$audit{check_marcfield_215b} = defined $marcstructure->{'215'}->{'b'};
$audit{check_marcfield_219}  = defined $marcstructure->{'219'};
$audit{check_marcfield_325}  = defined $marcstructure->{'325'};
$audit{check_marcfield_338}  = defined $marcstructure->{'338'};
$audit{check_marcfield_371}  = defined $marcstructure->{'371'};
$audit{check_marcfield_930j} = defined $marcstructure->{'930'}->{'j'};
$audit{check_marcfield_930j_av_codepeb} = defined $marcstructure->{'930'}->{'j'} && $marcstructure->{'930'}->{'j'}->{'authorised_value'} eq 'CODEPEB';

say "009 : " . ($audit{check_marcfield_009}  ? $ok : $ko);
say "010a: " . ($audit{check_marcfield_010a} ? $ok : $ko);
say "011a: " . ($audit{check_marcfield_011a} ? $ok : $ko);
say "029 : " . ($audit{check_marcfield_029}  ? $ok : $ko);
say "033a: " . ($audit{check_marcfield_033a} ? $ok : $ko);
say "073a: " . ($audit{check_marcfield_073a} ? $ok : $ko);
say "1012: " . ($audit{check_marcfield_1012} ? $ok : $ko);
say "181c: " . ($audit{check_marcfield_181c} ? $ok : $ko);
say "182c: " . ($audit{check_marcfield_182c} ? $ok : $ko);
say "183c: " . ($audit{check_marcfield_183c} ? $ok : $ko);
say "214 : " . ($audit{check_marcfield_214}  ? $ok : $ko);
say "215b: " . ($audit{check_marcfield_215b} ? $ok : $ko);
say "219 : " . ($audit{check_marcfield_219}  ? $ok : $ko);
say "325 : " . ($audit{check_marcfield_325}  ? $ok : $ko);
say "338 : " . ($audit{check_marcfield_338}  ? $ok : $ko);
say "371 : " . ($audit{check_marcfield_371}  ? $ok : $ko);
say "930j: " . ($audit{check_marcfield_930j} ? $ok : $ko);
say "930j_av_codepeb: " . ($audit{check_marcfield_930j_av_codepeb} ? $ok : $ko);

say "\nCount records with fields";

($audit{count_marcfield_003}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//controlfield[@tag="003"])') > 0
});
say "003 : $audit{count_marcfield_003}";

($audit{count_marcfield_010a}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="010"]/subfield[@code="a"])') > 0
});
say "010a: $audit{count_marcfield_010a}";

($audit{count_marcfield_011a}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="011"]/subfield[@code="a"])') > 0
});
say "011a: $audit{count_marcfield_011a}";

($audit{count_marcfield_033a}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="033"]/subfield[@code="a"])') > 0
});
say "033a: $audit{count_marcfield_033a}";

($audit{count_marcfield_073a}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="073"]/subfield[@code="a"])') > 0
});
say "073a: $audit{count_marcfield_073a}";

($audit{count_marcfield_181c}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="181"]/subfield[@code="c"])') > 0
});
say "181c: $audit{count_marcfield_181c}";

($audit{count_marcfield_182c}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="182"]/subfield[@code="c"])') > 0
});
say "182c: $audit{count_marcfield_182c}";

($audit{count_marcfield_183c}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="183"]/subfield[@code="c"])') > 0
});
say "183c: $audit{count_marcfield_183c}";

($audit{count_marcfield_009}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//controlfield[@tag="009"])') > 0
});
say "009 : $audit{count_marcfield_009}";

($audit{count_marcfield_214}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="214"])') > 0
});
say "214 : $audit{count_marcfield_214}";

($audit{count_marcfield_219}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, 'count(//datafield[@tag="219"])') > 0
});
say "219 : $audit{count_marcfield_219}";

# count O33a contenant ark:/12148/
say "\nCount BnF ARK";
($audit{count_bnf_ark}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "%ark:/12148/%"
});
say $audit{count_bnf_ark};

# count 009 ou O33a contient PPN* ou sudoc.fr/* ou 009=[alphanum]
say "\nCount PPN";
($audit{count_sudoc_ppn}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "%sudoc.fr/%"
      OR ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "PPN%"
      OR ExtractValue(metadata, '//controlfield[@tag="009"]') LIKE "PPN%"
      OR ExtractValue(metadata, '//controlfield[@tag="009"]') LIKE "%sudoc.fr/%"
      OR ExtractValue(metadata, '//controlfield[@tag="009"]') REGEXP '^[A-Za-z0-9]+$'
});
say $audit{count_sudoc_ppn};

# count 033a qui n'ont ni ark ni ppn et les notices avec une valeur en 033a
say "\nCount Others 033a";
($audit{count_ids_in_033a}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) FROM biblio_metadata
    WHERE ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') NOT LIKE "%sudoc.fr/%"
      AND ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') NOT LIKE "PPN%"
      AND ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') NOT LIKE "%ark:/12148/%"
      AND ExtractValue(metadata, 'count(//datafield[@tag="033"]/subfield[@code="a"])') > 0
});
say $audit{count_ids_in_033a};

# count O33a contient un seul %ark:/12148/% ou un ark et un PPN ou un PPN
# (notice "alignée de manière unique avec un réservoir national")
# where  la combinatoire des clauses précédentes
# (count = 1 et like ark) ou (count = 1 et (like sudoc.com ou like ppn)) ou
# (count=2 et like ark et (like sudoc.com ou like ppn))
say "\nCount aligned Biblios";
($audit{count_aligned_biblios}) = $dbh->selectrow_array(q{
    SELECT COUNT(*) as count FROM biblio_metadata
    WHERE ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "%sudoc.fr/%"
      OR ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "PPN%"
      OR ExtractValue(metadata, '//datafield[@tag="033"]/subfield[@code="a"]') LIKE "%ark:/12148/%"
});
say $audit{count_aligned_biblios};

say "\nAuthorised values";
my @audit_av;
foreach my $category (qw(qualif LANG CODEPEB)) {
    my $ref_values = $dbh->selectcol_arrayref("SELECT authorised_value FROM koha_plugin_com_biblibre_transitionbibliographique_av WHERE category = ?", undef, $category);
    my $values = $dbh->selectcol_arrayref("SELECT authorised_value FROM authorised_values WHERE category = ?", undef, $category);

    my @missing_values = array_minus(@$ref_values, @$values);
    my @invalid_values = array_minus(@$values, @$ref_values);
    my @valid_values = intersect(@$ref_values, @$values);

    my @category_audit_av = (
        (map { { category => $category, authorised_value => $_, is_missing => 0, is_invalid => 0 } } @valid_values),
        (map { { category => $category, authorised_value => $_, is_missing => 1, is_invalid => 0 } } @missing_values),
        (map { { category => $category, authorised_value => $_, is_missing => 0, is_invalid => 1 } } @invalid_values),
    );
    @category_audit_av = sort { $a->{authorised_value} cmp $b->{authorised_value} } @category_audit_av;

    push @audit_av, @category_audit_av;

    say "\n$category";
    foreach my $av (@category_audit_av) {
        my $status = $av->{is_missing} ? red('✗ missing') :
            $av->{is_invalid} ? red('✗ invalid') : green('✓');
        say sprintf('%s: %s', $av->{authorised_value}, $status);
    }
}

my $audit_auth_results = $dbh->selectall_arrayref(
    "
        SELECT auth_types.authtypecode, IF(auth_subfield_structure.authtypecode IS NULL, 0, 1) check_marcfield_1012
        FROM auth_types LEFT JOIN auth_subfield_structure ON (
            auth_types.authtypecode = auth_subfield_structure.authtypecode
            AND auth_subfield_structure.tagfield = '101'
            AND auth_subfield_structure.tagsubfield = '2'
        )
        ORDER BY auth_types.authtypecode
    ",
    { Slice => {} },
);

say "\nAuthority types";
foreach my $result (@$audit_auth_results) {
    my $status = $result->{check_marcfield_1012} ? green('✓') : red('✗ missing');
    say sprintf('%10s 101$2: %s', $result->{authtypecode} || '[Default]', $status);
}

unless ($opts{'dry-run'}) {
    my @insert_set_clauses;
    my @insert_bind_values;
    while (my ($key, $value) = each %audit) {
        push @insert_set_clauses, sprintf('%s = ?', $dbh->quote_identifier($key));
        push @insert_bind_values, $value;
    }

    my $insert_sql = 'INSERT koha_plugin_com_biblibre_transitionbibliographique_audit_tb SET ' . join(', ', @insert_set_clauses);
    $dbh->do($insert_sql, undef, @insert_bind_values);
    my $audit_id = $dbh->last_insert_id();

    my $av_sth = $dbh->prepare('INSERT koha_plugin_com_biblibre_transitionbibliographique_audit_av SET audit_id = ?, category = ?, authorised_value = ?, is_missing = ?, is_invalid = ?');
    foreach my $av (@audit_av) {
        $av_sth->execute($audit_id, $av->{category}, $av->{authorised_value}, $av->{is_missing}, $av->{is_invalid});
    }

    my $auth_sth = $dbh->prepare('INSERT koha_plugin_com_biblibre_transitionbibliographique_audit_auth SET audit_id = ?, authtypecode = ?, check_marcfield_1012 = ?');
    foreach my $result (@$audit_auth_results) {
        $auth_sth->execute($audit_id, $result->{authtypecode}, $result->{check_marcfield_1012});
    }
}

#!/usr/local/bin/perl

use lib './lib';
use Ace;

$db = Ace->connect(-host=>'sapiens',-port=>123456,-path=>'~mieg/bin/aceclient');

my $ace = $db->fetch('Sequence','DBEST:20415');
print $ace->asString,"\n";

my $dna = $ace->DNA->pick;
print $dna->asString;

print "Identifier is ",join(' ',$ace->at('DB_info.identifier')->row),"\n";
print "Title is ", $ace->Title,"\n";

@h = $ace->DNA_homol;
print "First homology is $h[0]\n";

print "Clone is ",$ace->Clone,"\n More info:\n";
$clone=$ace->Clone->pick;
print $clone->asString;

my @objects = $db->list('Sequence','DBEST:2963*');
foreach (@objects) {
    print "$_: ",$_->Title,"\n";
}
print scalar(@objects)," objects\n";


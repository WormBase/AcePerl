#!/usr/local/bin/perl

use lib './lib';
use Ace;

$db = Ace->connect(-host=>'sapiens',-port=>123456,-path=>'~mieg/bin/aceclient');

$sequence = new Ace::Object('Sequence','Test2',$db);
$sequence->add("Origin.From_Database",GENBANK);
$sequence->add("Origin.Species",'Arabidopsis thaliana');
$sequence->add("Visible.Paper",Ace::Object->new('Paper','aarts_1995_m2115'));

print $sequence->asString,"\n\n";
print $sequence->commit;

$j = $db->fetch('Sequence','Test2');
print $j->asString if $j;

$j->replace('Origin.Species','Arabidopsis thaliana','Homo sapiens');
$j->commit;

$j = $db->fetch('Sequence','Test2');
print $j->asString if $j;


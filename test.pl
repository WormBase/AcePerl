#!/usr/local/bin/perl

use lib './lib';
use Ace;

$db = Ace->connect(-host=>'geneman',-port=>20000100,-path=>'~mieg/bin/aceclient');
@o = $db->list('Sequence','D2*');
$i = $o[0];
print join(" ",$i->row),"\n";
print join(" ",$i->tags),"\n";
print $i->asString;

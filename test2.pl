#!/usr/local/bin/perl

use lib './lib';
use Ace;

$db = Ace->connect(-host=>'localhost',-port=>200001,-path=>'~acedb/bin/aceclient');
@sequences = $db->list('Sequence','m*');

foreach (@sequences) {
  @r = $_->tags;
  print scalar(@r),"\n";
}

#!/usr/local/bin/perl

use lib '..','../blib/lib','../blib/arch';
use Ace;

use constant HOST => $ENV{ACEDB_HOST} || 'beta.crbm.cnrs-mop.fr';
use constant PORT => $ENV{ACEDB_PORT} || 20000100;

print STDERR "pipe the output to a file or a GIF displaying program\n";

$ace = Ace->connect(-host=>HOST,-port=>PORT);
$m4 = $ace->fetch('Sequence', 'AC3' );
($gif,$box) = $m4->asGif;
print $gif;

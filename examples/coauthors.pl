#!/usr/local/bin/perl

use lib '..';
use Ace;
use constant HOST => $ENV{ACEDB_HOST} || 'beta.crbm.cnrs-mop.fr';
use constant PORT => $ENV{ACEDB_PORT} || 20000100;
my $AUTHOR = "Meyer BJ";

$|=1;

print "Trying to establish connection...";
my $db = Ace->connect(-port=>PORT,-host=>HOST);
print "done\n";

print "Searching for ${AUTHOR}'s coauthors:\n";
my $iterator = $db->find_many(-query=>qq/Author IS "$AUTHOR"; >Paper; >Author/);
while (my $author = $iterator->next) {
  print $author,"\n";
}

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use lib './blib/lib','./blib/arch';

BEGIN {$| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use Ace;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $ptr = Ace::AceDB->new('formaggio.cshl.org',200001,25);
print $ptr ? "ok 2" : "not ok 2","\n";
my $data = $ptr->query("Find Sequence");
print $data ? "ok 3" : "not ok 3","\n";
my $db = Ace->connect(-host=>'formaggio.cshl.org',-port=>200001);
print $db ? "ok 4" : "not ok 4","\n";
my $obj = $db->fetch('Sequence','M4');
print $obj eq 'M4' ? "ok 5" : "not ok 5","\n";


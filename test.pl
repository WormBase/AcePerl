# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use lib './blib/lib','./blib/arch';

BEGIN {$| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use AcePerl;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $ptr = AcePerl::AceDB->new('localhost',200001,25);
print $ptr ? "ok 2" : "not ok 2","\n";
my $data = $ptr->query("Find Sequence");
print $data ? "ok 3" : "not ok 3","\n";

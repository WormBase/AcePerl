#!/usr/local/bin/perl -w

# Low level tests of connectivity
######################### We start with some black magic to print on failure.
use lib '../blib/lib','../blib/arch';
use constant HOST => $ENV{ACEDB_HOST} || 'beta.crbm.cnrs-mop.fr';
use constant PORT => $ENV{ACEDB_PORT} || 20000100;

BEGIN {$| = 1; print "1..11\n"; }
END {print "not ok 1\n" unless $loaded;}
use Ace qw/STATUS_WAITING STATUS_PENDING/;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

sub test {
    local($^W) = 0;
    my($num, $true,$msg) = @_;
    print($true ? "ok $num\n" : "not ok $num $msg\n");
}

# Test code:
my $ptr = Ace::AceDB->new(HOST,PORT,25);
test(2,$ptr,"connection failed");
test(3,$ptr->status() == STATUS_WAITING,"did not get wait status");
test(4,$ptr->query("Find Author"),"query() returned undef");
test(5,$ptr->status() == STATUS_PENDING,"did not get pending status");
test(6,$ptr->read,"read failed");
test(7,$ptr->status() == STATUS_WAITING,"did not get wait status");
test(8,$ptr->query("List"),"query(list) returned undef");
my $loop = 0;
my $data;
while ($ptr->status()) { 
  $data = $ptr->read();
  $loop++;
}
test(9,$loop>1,"didn't get an encore status");
test(10,length($data)>0,"didn't get data");
test(11,$ptr->status() == STATUS_WAITING,"did not get waiting status");

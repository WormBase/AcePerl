#!/usr/local/bin/perl

# Tests of object-level fetches and following
######################### We start with some black magic to print on failure.
use lib '../blib/lib','../blib/arch';
use constant HOST => $ENV{ACEDB_HOST} || 'beta.crbm.cnrs-mop.fr';
use constant PORT => $ENV{ACEDB_PORT} || 20000100;

BEGIN {$| = 1; print "1..14\n"; }
END {print "not ok 1\n" unless $loaded;}
use Ace;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

sub test {
    local($^W) = 0;
    my($num, $true,$msg) = @_;
    print($true ? "ok $num\n" : "not ok $num $msg\n");
}

# Test code:
my ($db,$obj);
test(2,$db = Ace->connect(-host=>HOST,-port=>PORT),
     "couldn't establish connection");
test(3,$me = Ace::Object->new('Author','Stein LD',$db),"couldn't create new object");
test(4,$me->add('Full_name','Lincoln Stein'));
test(5,$me->add('Laboratory','FF'));
test(6,$me->add('Address.Mail','Cold Spring Harbor Laboratory'));
test(7,$me->add('Address.Mail','One Bungtown Road'));
test(8,$me->add('Address.Mail','Cold Spring Harbor, New York 11777'));
test(9,$me->add('Address.Mail','USA'));
test(10,$me->add('Address.Fax','1111111'));
test(11,$me->replace('Address.Fax','1111111','2222222'));
test(12,$me->add('Address.Phone','123456'));
test(13,$me->delete('Address.Phone'));
# Either the commit should succeed, or it should fail with a Write Access denied failure
test(14,$me->commit || Ace->error=~/Write access to database denied/i,"commit failure $ACE::ERR"); 

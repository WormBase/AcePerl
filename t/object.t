#!/usr/local/bin/perl -w

# Tests of object-level fetches and following
######################### We start with some black magic to print on failure.
use lib '../blib/lib','../blib/arch';
use constant HOST => $ENV{ACEDB_HOST} || 'beta.crbm.cnrs-mop.fr';
use constant PORT => $ENV{ACEDB_PORT} || 20000100;

BEGIN {$| = 1; print "1..30\n"; }
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
my ($db,$obj,@obj,$lab);
my $DATA = q{Address  Mail    The Sanger Centre
                 Hinxton Hall
                 Hinxton
                 Cambridge CB10 1SA
                 U.K.
         E_mail  jes@sanger.ac.uk
         Phone   1223-834244
                 1223-494958
         Fax     1223-494919
};
test(2,$db = Ace->connect(-host=>HOST,-port=>PORT),"connection failure");
test(3,$obj = $db->fetch('Author','Sulston JE'),"fetch failure");
test(4,$obj eq 'Sulston JE',"string overload failure");
test(5,@obj = $db->fetch('Author','Sulston*'),"wildcard failure");
test(6,@obj==2,"failed to recover two authors from Sulston*");
test(7,$obj->right eq 'Full_name',"auto fill failure");
test(8,$obj->Full_name->at eq 'John Sulston',"automatic method generation failure");
test(9,$obj->Full_name->pick eq 'John Sulston',"pick failure");
test(10,(@obj = $obj->Address->Mail->col) == 5,"col failure");
test(11,$lab = $obj->Laboratory->pick,"pick failure");
test(12,join(' ',sort($lab->tags)) eq 'Address CGC Staff',"tags failure");
test(13,$lab->at('CGC.Allele_designation')->at eq 'e',"compound path failure");
test(14,$obj->Address->asString eq $DATA,"asString() method");
test(15,$db->ping,"can't ping");
test(16,$db->classes,"can't count classes");
test(17,join(' ',sort $obj->fetch('Laboratory')->tags) eq "Address CGC Staff","fetch failure");
test(18,join(' ',$obj->Address->row) eq "Address Mail The Sanger Centre","row() failure");
test(19,join(' ',$obj->Address->row(1)) eq "Mail The Sanger Centre","row() failure");
test(20,@h=$obj->Address(2),"tag[2] failure");
test(21,@h==9,"tag[2] failure");
test(22,$iterator1 = $db->fetch_many('Author','S*'),"fetch_many() failure (1)");
test(23,$iterator2 = $db->fetch_many('Clone','*'),"fetch_many() failure (2)");
test(24,$obj1 = $iterator1->next,"iterator failure (1)");
test(25,!$obj1->filled,"got filled object, expected unfilled");
test(26,($obj2 = $iterator1->next) && $obj1 ne $obj2,"iterator failure (2)");
test(27,($obj3 = $iterator2->next) && $obj3->class eq 'Clone',"iterator failure (3)");
test(28,($obj4 = $iterator1->next) && $obj4->class eq 'Author',"iterator failure (4)");
test(29,$iterator1 = $db->fetch_many(-class=>'Author',-name=>'S*',-filled=>1),"fetch_many(filled) failure");
test(30,($obj1 = $iterator1->next) && $obj1 && $obj1->filled,"expected filled object, got unfilled or null");

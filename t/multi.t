#!/usr/local/bin/perl -w

# Tests of Ace::Sequence::Multi
######################### We start with some black magic to print on failure.
use lib '..','../blib/lib','../blib/arch';
use constant HOST => 'stein.cshl.org';
use constant REFDB => 300000;
use constant ANN1  => 300001;
use constant ANN2  => 300002;

BEGIN {$| = 1; print "1..12\n"; }
END {print "not ok 1\n" unless $loaded;}
use Ace::Sequence::Multi;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

sub test {
    local($^W) = 0;
    my($num, $true,$msg) = @_;
    print($true ? "ok $num\n" : "not ok $num $msg\n");
}

unless (eval 'require Ace::RPC' ) {
  print "ok $_ # Skip, need Ace::RPC for this test\n" foreach (2..12);
}

test(2,$refdb = Ace->connect(-host=>HOST,-port=>REFDB,-timeout=>50),"connection failure to reference db");
test(3,$db1 = Ace->connect(-host=>HOST,-port=>ANN1,-timeout=>50),"connection failure to first annotation db");
test(4,$db2 = Ace->connect(-host=>HOST,-port=>ANN2,-timeout=>50),"connection failure to second annotation db");

die "Couldn't establish connection to database.  Aborting tests.\n" unless $refdb && $db1 && $db2;

# start with a clone from the reference database
test(5,$clone = $refdb->fetch(Sequence=>'ZK154'),"fetch failure");

# create a new Ace::Sequence::Multi object
test(6,$zk154 = Ace::Sequence::Multi->new(-seq => $clone,
					  -secondary => [$db1,$db2]
					 ),"new() failure");

# fetch all intron features
test(7,@introns = $zk154->features('intron'));

# any intron of subtype "intuition" comes from annot2 database
# any intron of subtype "Genefinder" comes from annot1 database
foreach (@introns) {
  $subtypes{$_->subtype}++;
}
test(8,$subtypes{'Genefinder'},"didn't retrieve annot1 annotations");
test(9,$subtypes{'intuition'},"didn't retrieve annot2 annotations");

# if dna is present, then the reference database did its job
test(10,$dna = $introns[0]->dna,"couldn't get DNA from refdb");
test(11,length($dna) > 0,"DNA not positive length");
test(12,$dna=~/[gatc]/,"DNA doesn't look like DNA");

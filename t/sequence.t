#!/usr/local/bin/perl -w

# Tests of object-level fetches and following
######################### We start with some black magic to print on failure.
use lib '../blib/lib','../blib/arch';
use constant HOST => $ENV{ACEDB_HOST} || 'stein.cshl.org';
use constant PORT => $ENV{ACEDB_PORT} || 200005;

BEGIN {$| = 1; print "1..40\n"; }
END {print "not ok 1\n" unless $loaded;}
use Ace::Sequence;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

sub test {
    local($^W) = 0;
    my($num, $true,$msg) = @_;
    print($true ? "ok $num\n" : "not ok $num $msg\n");
}

test(2,$db = Ace->connect(-host=>HOST,-port=>PORT,-timeout=>50),"connection failure");
die "Couldn't establish connection to database.  Aborting tests.\n" unless $db;

# test whole clones
test(3,$clone = $db->fetch(Sequence=>'ZK154'),"fetch failure");

test(4,$zk154 = Ace::Sequence->new($clone),"new() failure");
test(5,$zk154->start==1,"start() failure");
test(6,$zk154->end==26547,"end() failure");

test(7,$zk154s = Ace::Sequence->new(-seq=>$clone,
				    -offset=>100,
				    -length=>100),"new() failure (2)");
test(8,$zk154s->start==101,"start() failure (2)");
test(9,$zk154s->end==200,"end() failure (2)");

test(10,$zk154s->length==100,"length() failure");
test(11,length($zk154s->dna)==100,"dna() failure");

test(12,$zk154r = Ace::Sequence->new(-seq=>$clone,
				     -offset =>  100,
				     -length => -100),"new() failure (3)");
test(13,$zk154r->start==101,"start() failure (3)");
test(14,$zk154r->end==2,"end() failure (3)");

test(15,$zk154r->length==-100,"length() failure");
test(16,length($zk154r->dna)==100,"dna() failure");

@features = sort { $a->start <=> $b->start; }  $zk154->features('exon');

test(17,@features,'features() error');

test(18,$features[0]->start == 2527,'features()->start error');
test(19,$features[0]->end   == 2629,'features()->end error');

test(20,$gff = $zk154->gff,'gff() error');

if (eval q{local($^W)=0; require GFF;}) {
#  print STDERR "Expect a seek() on unopened file error from GFF module...\n";
  test(21,$gff = $zk154->GFF,'GFF() error');
} else {
  print "21 OK # Skip\n";
}

# Test that we can do the same thing on forward and reverse predicted genes
test(22,$gene = $db->fetch(Predicted_gene=>'ZK154.1'),"fetch failure (2)");
test(23,$zk154_1 = Ace::Sequence->new($gene),"new() failure (4)");
test(25,$zk154_1->start == 1,"start() failure (4)");
@features = sort { $a->start <=> $b->start; }  $zk154_1->features('exon');
test(26,$features[0]->start == 1,'features() error (2)');
test(27,$features[0]->end == 128,'features() error (2)');
test(28,length($features[0]->dna) == 128,'dna() error (3)');

# ZK154.3 is a reversed gene
test(29,$gene = $db->fetch(Predicted_gene=>'ZK154.3'),"fetch failure (3)");
test(30,$zk154_3 = Ace::Sequence->new($gene),"new() failure (5)");
test(31,$zk154_3->start == 1,"start() failure (5)");
test(32,$zk154_3->end == 1596,"start() failure (5)");
@features = $zk154_3->features('exon');
@features = sort { $a->start <=> $b->start; }  @features;
test(33,$features[0]->start == 1,'features() error (3)');
test(34,$features[0]->end == 57,'features() error (3)');
test(35,length($features[0]->dna) == 57,'dna() error (4)');

# test that relative offsets are working
$zk154 = Ace::Sequence->new(-seq=>$gene,-length=>11);
$zk154_3 = Ace::Sequence->new(-seq=>$gene,-offset=>1,-length=>10);
test(36,substr($zk154->dna,1,10) eq $zk154_3->dna,'offset error');


# Test that absolute coordinates are working
test(37,$zk154_3 = Ace::Sequence->new(-seq=>$gene,-refseq=>'CHROMOSOME_X'),'absolute coordinate error(1)');
test(38,$zk154_3->end-$zk154_3->start+ 1 == 1596,'absolute coordinate error(2)');
@features = sort {$a->start <=> $b->start } $zk154_3->features('exon');
test(39,@features,'absolute coordinate error(4)');
test(40,$features[$#features]->end-$features[$#features]->start+1 == 57,'absolute coordinate error(5)');




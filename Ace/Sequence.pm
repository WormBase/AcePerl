package Ace::Sequence;
use strict;

use Carp;
use strict;
use Ace 1.50 qw(:DEFAULT rearrange);
use Ace::Sequence::FeatureList;
use Ace::Sequence::Feature;
use AutoLoader 'AUTOLOAD';

use overload '""' => 'asString';
*abs_start  = \&start;
*abs_end    = \&end;
*parent_seq = \&parent;

# object constructor
# usually called like this:
# $seq = Ace::Sequence->new($object);
# but can be called like this:
# $seq = Ace::Sequence->new(-db=>$db,-name=>$name);
# or
# $seq = Ace::Sequence->new(-seq    => $object,
#                           -offset => $offset,
#                           -length => $length,
#                           -ref    => $refseq
#                           );
# $refseq, if provided, will be used to establish the coordinate
# system.  Otherwise the first base pair will be set to 1.
sub new {
  local $^W = 0;
  my $pack = shift;
  my ($obj,$offset,$len,$refseq,$db,$name) = 
    rearrange([
	       ['SEQ','SEQUENCE','SOURCE'],
	       ['OFFSET','OFF'],
	       ['LENGTH','LEN'],
	       'REFSEQ',
	       ['DATABASE','DB'],
	       'NAME'],@_);

  # Object must have a parent sequence and/or a reference
  # sequence.  In some cases, the parent sequence will be the
  # object itself.  The reference sequence is used to set up
  # the frame of reference for the coordinate system.

  # fetch the sequence object if we don't have it already
  croak "Please provide either a Sequence object or a database and name"
    unless defined $obj || ($name && $db);

  $obj ||= $db->fetch('Sequence'=>$name);
  unless ($obj) {
    Ace->error("No Sequence named $obj found in database");
    return;
  }
  
  my ($parent,$p_offset,$p_length,$source_reversed);
  ($obj,$parent,$p_offset,$p_length,$source_reversed) = _get_refseq($obj,$refseq);
  unless ($obj) {
    Ace->error("Unable to find a useable Sequence to use as the source");
    return;
  }

#  $len +=2 if defined $len && $len < 0 && $p_length > 0; # to correct for 1-based coordinates
#  $len -=2 if defined $len && $len > 0 && $p_length < 0; # to correct for 1-based coordinates
  my $native_length = 0;

  if ($p_length >= 0 || $source_reversed) {  # We are oriented positive relative to parent
    $native_length = $p_length if $source_reversed; # bug in Ace?
    $p_offset += $offset if defined $offset;
    $p_length =  $len if defined $len;
  } else {
    $p_offset -= $offset if defined $offset;
    $p_length =  -$len if defined $len;
  }


  # store the object into our instance variables and return
  return bless {
		'obj'           => $obj,
		'parent'        => $parent,
		'offset'        => $p_offset,
		'length'        => $p_length,
		'norelative'    => defined $refseq,
		'refseq'        => $refseq,
		'source_reversed' => CORE::abs($native_length),
	       },$pack;
}

# Toggle between absolute and relative coordinates
# "Absolute" coordinates is relative to the reference sequence.
#            and (+) strand is TRUE (+) strand
# "Relative" coordinates is relative to the source sequence.
sub abs {
  my $self = shift;
  $self->{'norelative'} = $_[0] if defined $_[0];
  return $self->{'norelative'};
}

# return the "source" object that the user offset from
sub source_seq { return $_[0]->{'obj'}; }

# return the parent object (which sets the coordinate system)
sub parent { return $_[0]->{'parent'}; }

# return starting position in absolute (source) coordinates
sub start {  return  $_[0]->offset + 1; }

# offset is in 0 based coordinates
sub offset { return $_[0]->{'offset'}; }

# return ending position in absolute (source) coordinates
sub end  {  
  return $_[0]->{'offset'} + CORE::abs($_[0]->{'length'}) if $_[0]->{'source_reversed'}; #special case
  my $end = $_[0]->{'offset'} + $_[0]->{'length'};
  $end +=2 if $_[0]->reversed;
  return $end;
}

# return length
sub length { 
#  return $_[0]->{'length'} > 0 ? $_[0]->{'length'} : $_[0]->{'length'}-2; 
  return $_[0]->end  - $_[0]->start -  1 if $_[0]->reversed;
  return $_[0]->end - $_[0]->start + 1;
}

# return whether we are reversed
sub reversed { 
  return $_[0]->{'length'} < 0; 
}

sub gff_reversed {
  return if $_[0]->{'source_reversed'};
  return $_[0]->reversed;
}

# __END__

#AUTOLOADED METHODS

# human readable string (for debugging)
sub asString {
  my $self = shift;
  return join '',$self->{'parent'},'/',$self->start,',',$self->end;
}

# return reference sequence
sub ref_seq {
  my $self = shift;
  return $self->abs ? $self->{'refseq'} || $self->{'parent'} : $self->{'parent'};
}

# return the database this sequence is associated with
sub db {
  return $_[0]->source_seq->db;
}

# Return the DNA
sub dna {
  my $self = shift;
  return $self->{dna} if $self->{dna};
  my $raw = $self->_query(undef,'seqdna');
  $raw=~s/^>.*\n//;
  $raw=~s/^\/\/.*//mg;
  $raw=~s/\n//g;
  $raw =~ s/\0+\Z//; # blasted nulls!
  _complement(\$raw) if $self->gff_reversed;
  return $self->{dna} = $raw;
}

# return a gff file
sub gff {
  my $self = shift;
  my ($abs,$features,$db) = rearrange([['ABS','ABSOLUTE'],'FEATURES','DB'],@_);
  $abs = $self->abs unless defined $abs;

  # can provide list of feature names, such as 'similarity', or 'all' to get 'em all
  #  !THIS IS BROKEN; IT SHOULD LOOK LIKE FEATURE()!
  my $opt = $self->_feature_filter($features);

  $db ||= $self->db;
  my $gff = $self->_gff($db,$opt);
  $self->transformGFF(\$gff) unless $abs;
  return $gff;
}

# return a GFF object using the optional GFF.pm module
sub GFF {
  my $self = shift;
  my ($filter,$converter) = @_;  # anonymous subs
  croak "GFF module not installed" unless require GFF;
  require GFF::Filehandle;

  my @lines = grep !/^\/\//,split "\n",$self->gff(@_);
  local *IN;
  local ($^W) = 0;  # prevent complaint by GFF module
  tie *IN,'GFF::Filehandle',\@lines;
  my $gff = GFF::GeneFeatureSet->new;
  $gff->read(\*IN,$filter,$converter) if $gff;
  return $gff;
}

# Get the features table.  Can filter by type/subtype this way:
# features('similarity:EST','annotation:assembly_tag')
sub features {
  my $self = shift;

  # parse out the filter
  my %filter;
  foreach (@_) {
    my ($type,$filter) = split(':');
    $filter{$type} = $filter;
  }
  
  # create pattern-match sub
  my $sub;
  if (%filter) {
    my $s = "sub { my \@d = split(\"\\t\",\$_[0]);\n";
    for my $type (keys %filter) {
      my $expr;
      my $subtype = $filter{$type};
      if (defined($type) && defined($subtype)) {
	$expr = "return 1 if \$d[2]=~/$type/i && \$d[1]=~/$subtype/i;\n"
      } else {
	$expr = defined($subtype) ? "return 1 if \$d[1]=~/$subtype/i;\n" 
                                  : "return 1 if \$d[2]=~/$type/i;\n" 
      }
      $s .= $expr;
    }
    $s .= "return;\n }";
    $sub = eval $s;
    croak $@ if $@;
  } else {
    $sub = sub { 1; }
  }
  # get raw gff file
  my $gff = $self->gff('-abs'=>1,-features=>[keys %filter]);

  my @features = map {Ace::Sequence::Feature->new($_,$self,$self->{norelative})} 
                 grep !m@^(?:\#|//)@ && $sub->($_),split("\n",$gff);

  return wantarray ? @features : \@features;
}

# return list of features quickly
sub feature_list {
  my $self = shift;
  return $self->{'feature_list'} if $self->{'feature_list'};
  return unless my $raw = $self->_query(undef,'seqfeatures -version 2 -list');
  return $self->{'feature_list'} = Ace::Sequence::FeatureList->new($raw);
}

# transform a GFF file into the coordinate system of the sequence
sub transformGFF {
  my $self = shift;
  my $gff = shift;
  my $offset = $self->offset;
  my $reversed = $self->gff_reversed;
  return unless $offset || $reversed;
  
  $offset += 2 if $reversed; # nasty 1-based indexing...

  # find anything that looks like a numeric field and subtract offset from it
  $$gff =~ s/\t(-?\d+)/"\t" . ($1 - $offset)/eg;

  # if we're reversed, then swap first and second postion fields and change strand
  return unless $reversed;
  $$gff =~ s/\t(-?\d+)\t(-?\d+)\t(\S)\t(\S)/join "\t",'',0-$2,0-$1,$3,$4 eq '+'? '-' : '+'/eg;
  $$gff =~ s/(\#\#sequence-region.+)$/$1(reversed)/m; # warn them!
}

# return a name for the object
sub name {
  return shift->source_seq->name;
}

# strand
sub strand {
  return $_[0]->reversed ? '-' : '+';
}

# user API routine to get the parent of the sequence as an
# Ace::Sequence object.
sub get_parent {
  my $self = shift;
  my $obj = $self->source_seq;  # always an Ace::Object... I hope
  my $prev;
  while ($obj) {
    $prev = $obj;
    $obj = _get_source($obj);
  }
  return unless $prev;
  return ref($self)->new($prev);
}

# return all children of this sequence
sub get_children {
  my $self = shift;
  my $obj = $self->source_seq;  # always an Ace::Object... I hope
  my @subs = $obj->S_Child(2);
  @subs    = $obj->Subsequence unless @subs;
  return map { $_->fetch } @subs;
}

# length in absolute terms
sub abslength {
  return CORE::abs($_[0]->length);
}

###################### internal functions #################
# not necessarily object-oriented!!

# this crucial routine traverses the parents upwards until it
# finds an object that is suitable for using as the reference
# in the call to seqfeatures.  Returns a three-element list consisting
# of the reference sequence, the offset from the reference sequence
# to the start of the requested sequence (0-based indexing), and the
# length of the sequence (which may be negative, if its orientation is
# reversed).  If $refseq is provided as the second argument, then it
# forces the subroutine to use that coordinate system.
sub _get_refseq {
  local $^W = 0;
  my ($obj,$refseq) = @_;
  my $o = $obj;
  my ($parent,$offset,$length,$source_reversed) = (undef,0,0,0); # to avoid uninitialized variable warnings

  # If we're passed a Sequence::Feature, then we can pull the
  # information we need right out of the fields
  if ( $obj->isa('Ace::Sequence') ) {
    $o      = $obj->isa('Ace::Sequence::Feature') ? $obj->parent->parent : $obj->source_seq;
    $parent = $obj->isa('Ace::Sequence::Feature') ? $o : $obj->parent;
    unless ($obj->abs_reversed) {
      $offset = $obj->abs_start - 1;
      $length = $obj->abs_end - $obj->abs_start + 1;
    } else {
      $offset = $obj->abs_end - 1;
      $length = $obj->abs_start - $obj->abs_end - 1;
    }
  } elsif ($obj->isa('Ace::Object')) {
    ($parent,$offset,$length) = _traverse($obj);
    $length -= 2 if $length < 0;  # to adjust for reversed sequences
    $source_reversed++ if $length < 0 && $obj->class eq 'Sequence';
  } else {
    croak "Source sequence not an Ace::Object or an Ace::Sequence";
  }

  if (defined $refseq) {
    my $db = $obj->db;
    $refseq = $db->fetch('Sequence'=>$refseq) unless ref $refseq;
    return unless $refseq;
    croak "Reference sequence must be an actual Sequence object"  unless $refseq->class eq 'Sequence';
    
    # find coordinates of $parent relative to coordinates of refseq
    my (@coords) = ('-coords',$offset+1,$offset+2);
    my $gff = $db->raw_query("gif seqget $parent ; seqfeatures  @coords -refseq $refseq -version 2 -feature DUMMY");
    my ($start,$end,$reverse) = $gff =~ /^\#\#sequence-region \S+ ([\d-]+) ([\d-]+)\s*?(\S*)$/m;
    unless ($start) {
      Ace->error('Sequence not contained within reference sequence');  # BIG assumption
      return;
    }
    $offset = $start - 1;
    $parent = $refseq;
  }

  return ($o,$parent,$offset,$length,$source_reversed);
}

# get sequence, offset and length for use as source
sub _traverse {
  my $obj = shift;

  my ($offset,$length,$prev) = (0,0,undef);

  # if object is a Sequence, and is associated with a DNA, then we
  # just return it
  if ( ($obj->class eq 'Sequence') && ( defined ($length = $obj->get(DNA=>2))) ) {
    return ($obj,0,$length);
  }

  # traverse upwards until we find a valid sequence object
  # that we can use for a call to seqfeatures
  for ($prev=$obj,my $o=_get_source($obj); 
       $o && !$length;
       $prev=$o,$o=_get_source($o)) {
    my $seq = _get_child($o,$prev);
    my ($start,$end) = $seq->row(1);
    $length ||= $end - $start + 1;
    $offset += $start - 1;
  }

  return ( $obj,0,$length ) if $obj->class eq 'Sequence';

  # Unfortunately, traversal  will fail in the event that a top-level sequence
  # is requested (like a whole CHROMOSOME).  In this case, we try to
  # derive its size from its DNA first, and if that doesn't work, from its
  # map information
#  $length ||= $obj->get(DNA=>2);

  unless ($length) {
    my @pieces = $obj->get(S_Child=>2);
    @pieces    = $obj->get('Subsequence') unless @pieces;
    foreach (@pieces) {
      my ($start,$end) = $_->row(1);
      $length = $start if $length < $start;
      $length = $end   if $length < $end;
    }
    $offset = 0;
    $prev   = $obj;
  }
  return ($prev,$offset,$length);
}

# this nasty routine is necessary in order to handle the
# transition from the magic Source tag to the magic
# S_Parent tag
sub _get_source {
  my $obj = shift;
  my $p = $obj->get(S_Parent=>2)|| $obj->get(Source=>1);
  return unless $p;
  return $p->fetch;
}

# This nasty routine is responsible for finding where the
# child sequence is in a parent.  handles backward compatibility
# with Subsequence and S_Child
sub _get_child {
  my ($obj,$target) = @_;
  my @subs = $obj->get(S_Child => 2);
  @subs    = $obj->get('Subsequence') unless @subs;
  my @s = grep $target eq $_,@subs;
  return $s[0]
}

# low level GFF call, no changing absolute to relative coordinates
sub _gff {
  my $self = shift;
  my $db = shift;
  my $data = $self->_query($db,"seqfeatures -version 2 @_");
  $data =~ s/\0+\Z//;
  return $data; #blasted nulls!
}

# shortcut for running a query
sub _query {
  my $self = shift;
  my $db = shift;
  return unless $self->source_seq && ($db ||= $self->source_seq->db);

  my $command = shift;
  my $name = $self->parent->name;
  my $start = $self->start;
  my $end   = $self->end;
  ($start,$end) = ($end,$start) if $start > $end;  #flippity floppity
  my $coord   = "-coords $start $end";
  $command .= " -refseq $self->{'parent'}" if $self->{'norelative'};

  # corrects a ?bug in ace server
  if ( $self->{'source_reversed'} && !$self->{'norelative'} ) {
    my $length = $self->{'source_reversed'};
    my $t_coord   = "-coords 1 $length";
    return $db->raw_query("gif seqget $name $t_coord ; $command $coord");
  } else {
    return $db->raw_query("gif seqget $name $coord ; $command");
  }
}

# utility function -- reverse complement
sub _complement {
  my $dna = shift;
  $$dna =~ tr/GATCgatc/CTAGctag/;
  $$dna = scalar reverse $$dna;
}

sub _feature_filter {
  my $self = shift;
  my $features = shift;
  return '' unless $features;
  my $opt = '';
  $opt = '-feature ' . join('|',@$features) if ref($features) eq 'ARRAY' && @$features;
  $opt = "-feature $features" unless ref $features;
  $opt;
}

1;

=head1 NAME

Ace::Sequence - Examine ACeDB Sequence Objects

=head1 SYNOPSIS

    # open database connection and get an Ace::Object sequence
    use Ace::Sequence;

    $db  = Ace->connect(-host => 'stein.cshl.org',-port => 200005);
    $obj = $db->fetch(Predicted_gene => 'ZK154.3');

    # Wrap it in an Ace::Sequence object 
    $seq = Ace::Sequence->new($obj);

    # Find all the exons
    @exons = $seq->features('exon');

    # Find all the exons predicted by various versions of "genefinder"
    @exons = $seq->features('exon:genefinder.*');

    # Iterate through the exons, printing their start, end and DNA
    for my $exon (@exons) {
      print join "\t",$exon->start,$exon->end,$exon->dna,"\n";
    }

    # Find the region 1000 kb upstream of the first exon
    $sub = Ace::Sequence->new(-seq=>$exons[0],
                              -offset=>-1000,-length=>1000);

    # Find all features in that area
    @features = $sub->features;

    # Print its DNA
    print $sub->dna;

    # Create a new Sequence object from the first 500 kb of chromosome 1
    $seq = Ace::Sequence->new(-name=>'CHROMOSOME_I',-db=>$db,
			      -offset=>0,-length=>500_000);

    # Get the GFF dump as a text string
    $gff = $seq->gff;

    # Limit dump to Predicted_genes
    $gff_genes = $seq->gff(-features=>'Predicted_gene');

    # Return a GFF object (using optional GFF.pm module from Sanger)
    $gff_obj = $seq->GFF;

=head1 DESCRIPTION

I<Ace::Sequence>, and its allied classes L<Ace::Sequence::Feature> and
L<Ace::Sequence::FeatureList>, provide a convenient interface to the
ACeDB Sequence classes and the GFF sequence feature file format.

Using this class, you can define a region of the genome by using a
landmark (sequenced clone, link, superlink, predicted gene), an offset
from that landmark, and a distance.  Offsets and distances can be
positive or negative.  This will return an I<Ace::Sequence> object.
Once a region is defined, you may retrieve its DNA sequence, or query
the database for any features that may be contained within this
region.  Features can be returned as objects (using the
I<Ace::Sequence::Feature> class), as GFF text-only dumps, or in the
form of the GFF class defined by the Sanger Centre's GFF.pm module.

This class builds on top of L<Ace> and L<Ace::Object>.  Please see
their manual pages before consulting this one.

=head1 Creating New Ace::Sequence Objects, the new() Method

 $seq = Ace::Sequence->new($object);

 $seq = Ace::Sequence->new(-source  => $object,
                           -offset  => $offset,
                           -length  => $length,
			   -refseq  => $reference_sequence);

 $seq = Ace::Sequence->new(-name    => $name,
			   -db      => $db,
                           -offset  => $offset,
                           -length  => $length,
			   -refseq  => $reference_sequence);

In order to create an I<Ace::Sequence> you will need an active I<Ace>
database accessor.  Sequence regions are defined using a "source"
sequence, an offset, and a length.  Optionally, you may also provide a
"reference sequence" to establish the coordinate system for all
inquiries.  Sequences may be generated from existing I<Ace::Object>
sequence objects, from other I<Ace::Sequence> and
I<Ace::Sequence::Feature> objects, or from a sequence name and a
database handle.

The class method named new() is the interface to these facilities.  In
its simplest, one-argument form, you provide new() with a
previously-created I<Ace::Object> that points to Sequence or
sequence-like object (the meaning of "sequence-like" is explained in
more detail below.)  The new() method will return an I<Ace::Sequence>
object extending from the beginning of the object through to its
natural end.

In the named-parameter form of new(), the following arguments are
recognized:

=over 4

=item -source

The sequence source.  This must be an I<Ace::Object> of the "Sequence" 
class, or be a sequence-like object containing the SMap tag (see
below).

=item -offset

An offset from the beginning of the source sequence.  The retrieved
I<Ace::Sequence> will begin at this position.  The offset can be any
positive or negative integer.  Offets are B<0-based>.

=item -length

The length of the sequence to return.  Either a positive or negative
integer can be specified.  If a negative length is given, the returned 
sequence will be complemented relative to the source sequence.

=item -refseq

The sequence to use to establish the coordinate system for the
returned sequence.  Normally the source sequence is used to establish
the coordinate system, but this can be used to override that choice.
You can provide either an I<Ace::Object> or just a sequence name for
this argument.  The source and reference sequences must share a common
ancestor, but do not have to be directly related.  An attempt to use a
disjunct reference sequence, such as one on a different chromosome,
will fail.

=item -name

As an alternative to using an I<Ace::Object> with the B<-source>
argument, you may specify a source sequence using B<-name> and B<-db>.
The I<Ace::Sequence> module will use the provided database accessor to
fetch a Sequence object with the specified name. new() will return
undef is no Sequence by this name is known.

=item -db

This argument is required if the source sequence is specified by name
rather than by object reference.

=back

If new() is successful, it will create an I<Ace::Sequence> object and
return it.  Otherwise it will return undef and return a descriptive
message in Ace->error().  Certain programming errors, such as a
failure to provide required arguments, cause a fatal error.

=head2 Reference Sequences and the Coordinate System

When retrieving information from an I<Ace::Sequence>, the coordinate
system is based on the sequence segment selected at object creation
time.  That is, the "+" strand is the natural direction of the
I<Ace::Sequence> object, and base pair 1 is its first base pair.  This
behavior can be overridden by providing a reference sequence to the
new() method, in which case the orientation and position of the
reference sequence establishes the coordinate system for the object.

In addition to the reference sequence, there are two other sequences
used by I<Ace::Sequence> for internal bookeeping.  The "source"
sequence corresponds to the smallest ACeDB sequence object that
completely encloses the selected sequence segment.  The "parent"
sequence is the smallest ACeDB sequence object that contains the
"source".  The parent is used to derive the length and orientation of
source sequences that are not directly associated with DNA objects.

In many cases, the source sequence will be identical to the sequence
initially passed to the new() method.  However, there are exceptions
to this rule.  One common exception occurs when the offset and/or
length cross the boundaries of the passed-in sequence.  In this case,
the ACeDB database is searched for the smallest sequence that contains 
both endpoints of the I<Ace::Sequence> object.

The other common exception occurs in Ace 4.8, where there is support
for "sequence-like" objects that contain the C<SMap> ("Sequence Map")
tag.  The C<SMap> tag provides genomic location information for
arbitrary object -- not just those descended from the Sequence class.
This allows ACeDB to perform genome map operations on objects that are
not directly related to sequences, such as genetic loci that have been
interpolated onto the physical map.  When an C<SMap>-containing object
is passed to the I<Ace::Sequence> new() method, the module will again
choose the smallest ACeDB Sequence object that contains both
end-points of the desired region.

If an I<Ace::Sequence> object is used to create a new I<Ace::Sequence>
object, then the original object's source is inherited.

=head1 Object Methods

Once an I<Ace::Sequence> object is created, you can query it using the
following methods:

=head2 asString()

  $name = $seq->asString;

Returns a human-readable identifier for the sequence in the form
I<Source/start-end>, where "Source" is the name of the source
sequence, and "start" and "end" are the endpoints of the sequence
relative to the source (using 1-based indexing).  This method is
called automatically when the I<Ace::Sequence> is used in a string
context.

=head2 source_seq()

  $source = $seq->source_seq;

Return the source of the I<Ace::Sequence>.

=head2 parent_seq()

  $parent = $seq->parent_seq;

Return the immediate ancestor of the sequence.  The parent of the
top-most sequence (such as the CHROMOSOME link) is itself.  This
method is used internally to ascertain the length of source sequences
which are not associated with a DNA object.

NOTE: this procedure is a trifle funky and cannot reliably be used to
traverse upwards to the top-most sequence.  The reason for this is
that it will return an I<Ace::Sequence> in some cases, and an
I<Ace::Object> in others.  Use get_parent() to traverse upwards
through a uniform series of I<Ace::Sequence> objects upwards.

=head2 ref_seq()

  $refseq = $seq->ref_seq;

Returns the reference sequence, if one is defined.

=head2 start()

  $start = $seq->start;

Start of this sequence, relative to the source sequence, using 1-based
indexing.

=head2 end()

  $end = $seq->end;

End of this sequence, relative to the source sequence, using 1-based
indexing.

=head2 offset()

  $offset = $seq->offset;

Offset of the beginning of this sequence relative to the source
sequence, using 0-based indexing.  The offset may be negative if the
beginning of the sequence is to the left of the beginning of the
source sequence.

=head2 length()
  
  $length = $seq->length;

The length of this sequence, in base pairs.  The length may be
negative if the sequence's orientation is reversed relative to the
source sequence.  Use abslength() to obtain the absolute value of
the sequence length.

=head2 abslength()

  $length = $seq->abslength;

Return the absolute value of the length of the sequence.

=head2 dna()

  $dna = $seq->dna;

Return the DNA corresponding to this sequence.  If the sequence length
is negative, the reverse complement of the appropriate segment will be
returned.

ACeDB allows Sequences to exist without an associated DNA object
(which typically happens during intermediate stages of a sequencing
project.  In such a case, the returned sequence will contain the
correct number of "-" characters.

=head2 name()

  $name = $seq->name;

Return the name of the source sequence as a string.

=head2 get_parent()

  $parent = $seq->parent;

Return the immediate ancestor of this I<Ace::Sequence> (i.e., the
sequence that contains this one).  The return value is a new
I<Ace::Sequence> or undef, if no parent sequence exists.

=head2 get_children()

  @children = $seq->get_children();

Returns all subsequences that exist as independent objects in the
ACeDB database.  What exactly is returned is dependent on the data
model.  In older ACeDB databases, the only subsequences are those
under the catchall Subsequence tag.  In newer ACeDB databases, the
objects returned correspond to objects to the right of the S_Child
subtag using a tag[2] syntax, and may include Predicted_genes,
Sequences, Links, or other objects.  The return value is a list of
I<Ace::Sequence> objects.

=head2 features()

  @features = $seq->features;
  @features = $seq->features('exon','intron','Predicted_gene');
  @features = $seq->features('exon:GeneFinder','Predicted_gene:hand.*');

features() returns an array of I<Sequence::Feature> objects.  If
called without arguments, features() returns all features that cross
the sequence region.  You may also provide a filter list to select a
set of features by type and subtype.  The format of the filter list
is:

  type:subtype

Where I<type> is the class of the feature (the "feature" field of the
GFF format), and I<subtype> is a description of how the feature was
derived (the "source" field of the GFF format).  Either of these
fields can be absent, and either can be a regular expression.  More
advanced filtering is not supported, but is provided by the Sanger
Centre's GFF module.

The order of the features in the returned list is not specified.  To
obtain features sorted by position, use this idiom:

  @features = sort { $a->start <=> $b->start } $seq->features;

=head2 feature_list()

  my $list = $seq->feature_list();

This method returns a summary list of the features that cross the
sequence in the form of a L<Ace::Feature::List> object.  From the
L<Ace::Feature::List> object you can obtain the list of feature names
and the number of each type.  The feature list is obtained from the
ACeDB server with a single short transaction, and therefore has much
less overhead than features().

See L<Ace::Feature::List> for more details.

=head2 gff()

  $gff = $seq->gff();
  $gff = $seq->gff(-abs      => 1,
                   -features => ['exon','intron:GeneFinder']);

This method returns a GFF file as a scalar.  The following arguments
are optional:

=over 4

=item -abs

Ordinarily the feature entries in the GFF file will be returned in
coordinates relative to the start of the I<Ace::Sequence> object.
Position 1 will be the start of the sequence object, and the "+"
strand will be the sequence object's natural orientation.  However if
a true value is provided to B<-abs>, the coordinate system used will
be relative to the start of the source sequence, i.e. the native ACeDB
Sequence object (usually a cosmid sequence or a link).  

If a reference sequence was provided when the I<Ace::Sequence> was
created, it will be used by default to set the coordinate system.
Relative coordinates can be reenabled by providing a false value to
B<-abs>.  

Ordinarily the coordinate system manipulations automatically "do what
you want" and you will not need to adjust them.  See also the abs()
method described below.

=item -features

The B<-features> argument filters the features according to a list of
types and subtypes.  The format is identical to the one described for
the features() method.  A single filter may be provided as a scalar
string.  Multiple filters may be passed as an array reference.

=back

See also the GFF() method described next.

=head2 GFF()

  $gff_object = $seq->gff;
  $gff_object = $seq->gff(-abs      => 1,
                   -features => ['exon','intron:GeneFinder']);

The GFF() method takes the same arguments as gff() described above,
but it returns a I<GFF::GeneFeatureSet> object from the GFF.pm
module.  If the GFF module is not installed, this method will generate 
a fatal error.

=head2 abs()

 $abs = $seq->abs;
 $abs = $seq->abs(1);

This method controls whether the coordinates of features are returned
in absolute or relative coordinates.  "Absolute" coordinates are
relative to the underlying source or reference sequence.  "Relative"
coordinates are relative to the I<Ace::Sequence> object.  By default,
coordinates are relative unless new() was provided with a reference
sequence.  This default can be examined and changed using abs().

=head2 db()

  $db = $seq->db;

Returns the L<Ace> database accessor associated with this sequence.

=head1 SEE ALSO

L<Ace>, L<Ace::Object>, L<Ace::Sequence::Feature>,
L<Ace::Sequence::FeatureList>, L<GFF>

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Many thanks to David Block <dblock@gene.pbi.nrc.ca> for finding and
fixing the nasty off-by-one errors.

Copyright (c) 1999, Lincoln D. Stein

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

__END__

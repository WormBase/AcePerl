package Ace::Sequence;
use strict;

use Carp;
use Ace 1.50 qw(:DEFAULT rearrange);
use Ace::Sequence::FeatureList;
use Ace::Sequence::Feature;
use AutoLoader 'AUTOLOAD';

use overload '""' => 'asString';
*abs_start = \&start;
*abs_end   = \&end;

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
  my $pack = shift;
  my ($obj,$offset,$len,$refseq,$db,$name) = 
    rearrange([
	       ['SEQ','SEQUENCE'],
	       ['OFFSET','OFF'],
	       ['LENGTH','LEN'],
	       'REFSEQ',
	       'DB',
	       'NAME'],@_);

  # Object must have a parent sequence and/or a reference
  # sequence.  In some cases, the parent sequence will be the
  # object itself.  The reference sequence is used to set up
  # the frame of reference for the coordinate system.
  $offset = 0 unless defined $offset;
  $len    = 0 unless defined $len;

  # fetch the sequence object if we don't have it already
  croak "Please provide either a Sequence object or a database and name"
    unless defined $obj || ($name && $db);

  $obj ||= $db->fetch('Sequence'=>$name);
  return unless $obj;      # No such object in database.

  return unless 
    my ($obj,$parent,$p_offset,$p_length) = _get_refseq($obj,$refseq);

  if ($p_length > 0) {  # We are oriented positive relative to parent
    $p_offset += $offset;
    $p_length =  $len if $len;
  } else {
    $p_offset -= $offset;
    $p_length =  -$len if $len;
  }

  # store the object into our instance variables and return
  return bless {
		'obj'           => $obj,
		'parent'        => $parent,
		'offset'        => $p_offset,
		'length'        => $p_length,
		'norelative'    => defined $refseq,
		'refseq'        => $refseq,
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
sub source { return $_[0]->{'obj'}; }

# return the parent object (which sets the coordinate system)
sub parent { return $_[0]->{'parent'}; }

# return starting position in absolute (source) coordinates
sub start {  return  $_[0]->offset + 1; }

# offset is in 0 based coordinates
sub offset { return $_[0]->{'offset'}; }

# return ending position in absolute (source) coordinates
sub end  {  return  $_[0]->{'offset'} + $_[0]->{'length'}; }

# return length
sub length { abs(return $_[0]->{'length'}); }

# return whether we are reversed
sub reversed { return $_[0]->{'length'} < 0; }

# human readable string (for debugging)
sub asString {
  my $self = shift;
  my $name = $self->source;
  return join '',$self->{parent},'/',$self->start,'-',$self->end;
}

# return reference sequence
sub refseq {
  my $self = shift;
  return $self->abs ? $self->{'refseq'} || $self->{'parent'} : $self->{'parent'};
}

# return a gff file
sub gff {
  my $self = shift;
  my ($abs,$features) = rearrange([['ABS','ABSOLUTE'],'FEATURES'],@_);
  $abs = $self->abs unless defined $abs;

  # can provide list of feature names, such as 'similarity', or 'all' to get 'em all
  my $opt = '';
  $opt = '-feature ' . join('|',@$features) if defined($features) 
                                                 && ref($features) eq 'ARRAY' 
						   && @$features;
  
  my $gff = $self->_gff($opt);
  $self->transformGFF(\$gff) unless $abs;
  return $gff;
}

# return a GFF object using the optional GFF.pm module
sub asGFF {
  my $self = shift;
  croak "GFF module not installed" unless require GFF;

  my @lines = grep !/^\/\//,split "\n",$self->gff(@_);
  local *IN;
  tie *IN,'GFF::Filehandle',\@lines;
  my $gff = GFF::GeneFeatureSet->new;
  $gff->read(\*IN) if $gff;
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
      my $subtype = $filter{$type};
      my $expr = $subtype ? "return 1 if \$d[2]=~/$type/i && \$d[1]=~/$subtype/i;\n"
                          : "return 1 if \$d[2]=~/$type/i;\n";
      $s .= $expr;
    }
    $s .= "return;\n }";
    $sub = eval $s;
    croak $@ if $@;
  } else {
    $sub = sub { 1; }
  }
  # get raw gff file
  my $gff = $self->gff(-abs=>1,-features=>[keys %filter]);
  my @features = map {Ace::Sequence::Feature->new($_,$self,$self->{norelative})} 
                 grep !m@^(?:\#|//)@ && $sub->($_),split("\n",$gff);

  return wantarray ? @features : \@features;
}

# return list of features quickly
sub feature_list {
  my $self = shift;
  return $self->{'feature_list'} if $self->{'feature_list'};
  return unless my $raw = $self->_query('seqfeatures -list');
  return $self->{'feature_list'} = Ace::Sequence::FeatureList->new($raw);
}

# transform a GFF file into the coordinate system of the sequence
sub transformGFF {
  my $self = shift;
  my $gff = shift;
  my $offset = $self->offset;
  return unless $offset || $self->reversed;
  
  $offset += 2 if $self->reversed; # nasty 1-based indexing...

  # find anything that looks like a numeric field and subtract offset from it
  $$gff =~ s/\t(-?\d+)/"\t" . ($1 - $offset)/eg;

  # if we're reversed, then swap first and second postion fields and change strand
  return unless $self->reversed;
  $$gff =~ s/\t(-?\d+)\t(-?\d+)\t(\S)\t(\S)/join "\t",'',0-$2,0-$1,$3,$4 eq '+'? '-' : '+'/eg;
  $$gff =~ s/(\#\#sequence-region.+)$/$1(reversed)/m; # warn them!
}

# return a name for the object
sub name {
  return shift->source->name;
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
  my ($obj,$refseq) = @_;
  my $o = $obj;
  my ($parent,$offset,$length);

  # If we're passed a Sequence::Feature, then we can pull the
  # information we need right out of the fields
  if ( $obj->isa('Ace::Sequence') ) {
    $o      = $obj->isa('Ace::Sequence::Feature') ? $obj->parent->parent : $obj->source;
    $parent = $obj->isa('Ace::Sequence::Feature') ? $o : $obj->parent;
    $offset = $obj->abs_start - 1;
    $length = $obj->abs_end - $obj->abs_start + 1;
  } elsif ($obj->isa('Ace::Object')) {
    ($parent,$offset,$length) = _traverse($obj);
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
    my $gff = $db->raw_query("gif seqget $parent @coords; seqfeatures -refseq $refseq -version 2 -feature DUMMY");
    my ($start,$end,$reverse) = $gff =~ /^\#\#sequence-region \S+ ([\d-]+) ([\d-]+)\s*?(\S*)$/m;
    unless ($start) {
      Ace->error('Sequence not contained within reference sequence');  # BIG assumption
      return;
    }
    $offset = $start - 1;
    $parent = $refseq;
  }

  return ($o,$parent,$offset,$length);
}

sub _traverse {
  my $obj = shift;

  # traverse upwards until we find a valid sequence object
  # that we can use for a call to seqfeatures
  my ($offset,$length,$prev) = (0,0,undef);
  for ($prev=$obj,my $o=_get_source($obj); 
       $o && $prev->class ne 'Sequence';
       $prev=$o,$o=_get_source($o)) {
    my $seq = _get_child($o,$prev);
    my ($start,$end) = $seq->row(1);
    $length ||= $end - $start + 1;
    $offset += $start - 1;
  }

  # Unfortunately, traversal  will fail in the event that a top-level sequence
  # is requested (like a whole CHROMOSOME).  In this case, we try to
  # derive its size from its DNA first, and if that doesn't work, from its
  # map information
  $length ||= $obj->get(DNA=>2);

  unless ($length) {
    my @pieces = $obj->get(S_Child=>2);
    @pieces    = $obj->get('Source') unless @pieces;
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
  my @subs = $obj->S_Child(2);
  @subs    = $obj->Subsequence unless @subs;
  my @s = grep $target eq $_,@subs;
  return $s[0]
}

# low level GFF call, no changing absolute to relative coordinates
sub _gff {
  my $self = shift;
  my $data = $self->_query("seqfeatures -version 2 @_");
  $data =~ s/\0+\Z//;
  return $data; #blasted nulls!
}

# shortcut for running a query
sub _query {
  my $self = shift;
  my $command = shift;
  my $name = $self->parent->name;
  my $start = $self->start;
  my $end   = $self->end;
  ($start,$end) = ($end,$start) if $start > $end;  #flippity floppity
  my $coord = "-coords $start $end";
  $command .= " -refseq $self->{parent}" if $self->{'norelative'};
  return unless $self->source && (my $db = $self->source->db);
  return $db->raw_query("gif seqget $name $coord ; $command");
}

1;
__END__

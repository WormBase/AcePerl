package Ace::Sequence;
use strict;

use Carp;
use Ace 1.50 qw(:DEFAULT rearrange);

# object constructor
# usually called like this:
# $seq = Ace::Sequence->new($object);
# but can be called like this:
# $seq = Ace::Sequence->new(-db=>$db,-name=>$name);
sub new {
  my $pack = shift;
  my ($obj,$offset,$len,$db,$name) = 
    rearrange(['SEQ',['OFFSET','OFF'],['LENGTH','LEN'],'DB','NAME'],@_);

  # fetch the sequence object if we don't have it already
  unless (defined $obj) {
    croak "Please provide either a Sequence object or a database and name" 
	unless $db && $name;
    $obj = $db->fetch('Sequence'=>$name);
    return unless $obj;  # No object in database.  Not necessarily an error.
  }

  # make sure that the object is really a sequence.
  # this is a little hoaky, because there's no way of really asking Ace for
  # object inheritance
  croak "\"$obj\" is not a Sequence" unless lc($obj->class) eq 'sequence';
  
  # store the object into our instance variables and return
  return bless {
		'obj'=>$obj,
		'offset' => $offset,
		'length' => $len,
	       },$pack;
}

# name of the thing
sub name {
  my $self = shift;
  return $self->_obj->name;
}

# Native length of the thing.
sub length {
  my ($start,$end) = shift->source_coord;
  return 0 unless defined $start;
  return 1 + $end - $start;
}

# Return the DNA
sub dna {
  my $self = shift;
  return $self->{dna} if $self->{dna};
  my $raw = $self->_query('seqdna');
  $raw=~s/^>.*\n//;
  $raw=~s/^\/\/.*//mg;
  $raw=~s/\n//g;
  return $self->{dna} = $raw;
}

# The "natural" object that contains this sequence
sub source {
  return unless my $basic_info = shift->_basic_info;
  return $basic_info->{source};
}

# return coordinates in the natural object
sub source_coord {
  return unless my $basic_info = shift->_basic_info;
  return ($basic_info->{source_start},$basic_info->{source_end});
}

# return a GFF version 2 table as a big string
sub gff {
  my $self = shift;
  return $self->_query("seqfeatures -version 2 @_");
}

# return a GFF object using the optional GFF.pm module
sub asGFF {
    my $self = shift;
    croak "GFF module not installed" unless eval "use GFF";
    my @lines = $self->gff;
    local *IN;
    tie *IN,'GFF::Filehandle',\@lines;
    return GFF->read(\*IN);
}

# Get feature lists without much overhead
sub features {
  my $self = shift;

  # no arguments , so just return skeleton of feature list
  return $self->_get_feature_list unless @_;

  # can provide list of feature names, such as 'similarity', or
  # 'all' to get 'em all
  my $all = 1 if grep lc($_) eq 'all',@_;
  my $opt = $all ? '' : '-feature ' . join('|',@_);
  
  # get raw gff file
  my $gff = $self->gff($opt);
  my @lines = grep !/^\#/,split("\n",$gff);
  return map {Ace::Sequence::Feature->new($_)} @lines;
}

# utility functions
sub _obj {
  return shift->{'obj'};
}

# offsets to coordinates
sub _coord {
  my $self = shift;
  return unless $self->{'length'};
  my $start = $self->{offset} + 1;
  my $end   = $start + $self->{'length'} - 1;
  return ($start,$end);
}

sub _query {
  my $self = shift;
  my $command = shift;
  my ($start,$end) = $self->_coord;
  my $name = $self->name;
  my $opt = defined($start) ? "-coords $start $end" : '';
  return $self->_obj->db->raw_query("gif seqget $name $opt ; $command");
}

# Create and cache info about the types and counts of features
sub _basic_info {
  my $self = shift;
  return $self->{'basic_info'} if $self->{'basic_info'};
  my $raw = $self->gff(-feature=>'DUMMY');
  return unless $raw;
  my ($date) = $raw =~ /^\#\#date\s+(\S+)/m;
  my ($source,$start,$end) = $raw =~ /^\#\#sequence-region (\S+) ([\d-]+) ([\d-]+)/m;
  return $self->{'basic_info'} = { 'date'         => $date,
				   'source'       => $source,
				   'source_start' => $start,
				   'source_end'   => $end,
				 };
}

sub _get_feature_list {
  my $self = shift;
  return $self->{'feature_list'} if $self->{'feature_list'};
  return unless my $raw = $self->_query('seqfeatures -list');
  return $self->{'feature_list'} = Ace::Sequence::FeatureList->new($raw);
}

package Ace::Sequence::FeatureList;

sub new {
  my $package =shift;
  my @lines = split("\n",$_[0]);
  my (%parsed);
  foreach (@lines) {
    next if m!^//!;
    my ($minor,$major,$count) = split "\t";
    next unless $count > 0;
    $parsed{$major}{$minor} = $count;
    $parsed{_TOTAL}++;
  }
  return bless \%parsed,$package;
}

# no arguments, scalar context -- count all features
# no arguments, array context  -- list of major types
# 1 argument, scalar context   -- count of major type
# 1 argument, array context    -- list of minor types
# 2 arguments                  -- count of subtype
sub types {
  my $self = shift;
  my ($type,$subtype) = @_;
  my $count = 0;

  unless ($type) {
    return wantarray ? grep !/^_/,keys %$self : $self->{_TOTAL};
  }

  unless ($subtype) {
    return keys %{$self->{$type}} if wantarray;
    foreach (keys %{$self->{$type}}) {
      $count += $self->{$type}{$_};
    }
    return $count;
  }
  
  return $self->{$type}{$subtype};
}

package Ace::Sequence::Feature;
use Carp;

# parse a line from a sequence list
sub new {
  my $class = shift;
  my ($gff_line,$db) = @_;
  croak "must provide a line from a GFF file"  unless $gff_line;
  return bless {db=>$db,data=>[split("\t",$gff_line)]},$class;
}

sub seqname  { _field(0,@_); }
sub source   { _field(1,@_); }  # I don't like this term...
sub subtype  { _field(1,@_); }  # ... I prefer "subtype"
sub feature  { _field(2,@_); }  # I don't like this term...
sub type     { _field(2,@_); }  # ... I prefer "type"
sub start    { _field(3,@_); }  # start of feature
sub end      { _field(4,@_); }  # end of feature
sub score    { _field(5,@_); }  # float indicating some sort of score
sub strand   { _field(6,@_); }  # one of +, - or undef
sub frame    { _field(7,@_); }  # one of 1, 2, 3 or undef
sub info     {                  # returns Ace::Object(s) containing further information about the feature
    my $info = _field(7,@_);    # be prepared to get an array of interesting objects!!!!
    return unless $info;
    my @data = split(/\s*;\s*/,$info);
    return map {$_[0]->toAce($_)} @data;
}

# map info into a reasonable set of ace objects
sub toAce {
    my $self = shift;
    my $thing = shift;
    my ($tag,@values) = $thing=~/(\"[^\"]+?\"|\S+)/g;
    foreach (@values) { # strip the damn quotes
	s/^\"(.*)\"$/$1/;  # get rid of leading and trailing quotes
    }
    return $self->tag2ace($tag,@values);
}

# syntesize an artificial Ace object based on the tag
sub tag2ace {
    my $self = shift;
    my ($tag,@data) = @_;

    # Sequence and Clone objects are easy to deal with.
    # Are there other easy cases?
    return Ace::Object->new($tag=>$data[0],$self->{'db'})
	if $tag eq 'Sequence' || $tag eq 'Clone';

    # for Notes we just return a text, no database associated
    return Ace::Object->new(Text=>$data[0]) if $tag eq 'Note';
    
    # for homols, we create the indicated Protein or Sequence object
    # then generate a bogus Homology object (for future compatability??)
    if ($tag eq 'Target') {
	my $db = $self->db;
	my ($objname,$start,$end) = @data;
	my ($class,$name) = $objname =~ /(\S+):(.+)/;
	my $obj   = $db->fetch($class=>$name);
	my $homol = Ace::Object->new('Homology'=>$self->source . "->$name");
	$homol->add_row('Target'=> $obj);
	$homol->add_row('Start' => $start);
	$homol->end_row('End'   => $end);
	return $homol;
    }

    # Default is to return a Text
    return Ace::Object->new(Text=>$data[0]);
}

# $_[0] is field no, $_[1] is self, $_[2] is optional replacement value
sub _field {
    my $v = defined $_[2] ? $_[1]->{data}->[$_[0]] = $_[2] 
                          : $_[1]->{data}->[$_[0]];
    return if $v eq '.';
    return $v;
}

# this is a dumb trick to work around GFF.pm's inability to take data 
# from memory
package GFF::Filehandle;

sub TIEHANDLE {
    my ($package,$datalines) = @_;
    return bless $datalines,$package;
}

sub READLINE {
    my $self = shift;
    return shift @$self;
}

1;

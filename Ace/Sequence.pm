package Ace::Sequence;
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
    croak "Please provide either a Sequence object or a database and name" unless $db && $name;
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
		'offset' => $off,
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
  
  $gff ;  #placeholder -- will return real object soon
}

# utility functions
sub _obj {
  return shift->{'obj'};
}

# offsets to coordinates
sub _coord {
  my $self = shift;
  return unless $self->{length};
  my $start = $self->{offset} + 1;
  my $end   = $start + $self->{length} - 1;
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
  return $self->{'basic_info'} = { date => $date,
				   source       => $source,
				   source_start => $start,
				   source_end   => $end,
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

# parse a line from a sequence list
sub new {
  my $class = shift;
  my ($gff_line,$db) = @_;
  croak "must provide a line from a GFF file"  unless $gff_line;
  my ($name,$source,$type,$start,$end,$score,$strand,$frame,$comment) = 
    split("\t",$gff_line);

}

1;

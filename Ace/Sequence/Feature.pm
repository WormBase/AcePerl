package Ace::Sequence::Feature;
use strict;

use Ace;
use Ace::Sequence::Homol;
use Carp;
use AutoLoader 'AUTOLOAD';
use vars '@ISA','%REV';
@ISA = 'Ace::Sequence';  # for convenience sake only
%REV = ('+' => '-', 
	'-' => '+');  # war is peace, &c.


use overload '""' => 'asString';

# parse a line from a sequence list
sub new {
  my $class = shift;
  my ($gff_line,$src,$norelative) = @_;
  croak "must provide a line from a GFF file"  unless $gff_line;
  return bless { parent     => $src,
		 data       => [split("\t",$gff_line)],
		 norelative => $norelative
	       },$class;
}

# $_[0] is field no, $_[1] is self, $_[2] is optional replacement value
sub _field {
    my $v = defined $_[2] ? $_[1]->{data}->[$_[0]] = $_[2] 
                          : $_[1]->{data}->[$_[0]];
    return if $v eq '.';
    return $v;
}

1;

__END__

sub parent { $_[0]->{'parent'}; }
sub db     { return $_[0]->{'db'} ||= $_[0]->parent->source->db; }
sub abs2rel { 
  $_[0]->parent->reversed ? 2 + $_[0]->parent->offset - $_[1] : $_[1] - $_[0]->parent->offset; 
}

sub seqname   { $_[0]->db->fetch(Sequence=>_field(0,@_)); }
sub source    { _field(1,@_); }  # I don't like this term...
sub method    { _field(1,@_); }  # ... I prefer "method"
sub subtype   { _field(1,@_); }  # ... or even "subtype"
sub feature   { _field(2,@_); }  # I don't like this term...
sub type      { _field(2,@_); }  # ... I prefer "type"
sub abs_start { _field(3,@_); }  # start, absolute coordinates
sub abs_end   { _field(4,@_); }  # end, absolute coordinates
sub score     { _field(5,@_); }  # float indicating some sort of score
sub strand    { !$_[0]->abs && $_[0]->parent->reversed ? 
		    $REV{_field(6,@_)} : 
		    _field(6,@_); }  # one of +, - or undef
sub reversed  { $_[0]->strand eq '-'; }
sub frame     { _field(7,@_); }  # one of 1, 2, 3 or undef
sub info      {                  # returns Ace::Object(s) with info about the feature
  my ($self) = @_;
  unless ($self->{'info'}) {
    my $info = _field(8,@_);    # be prepared to get an array of interesting objects!!!!
    return unless $info;
    my @data = split(/\s*;\s*/,$info);
    $self->{'info'} = [map {$_[0]->toAce($_)} @data];
  }
  return wantarray ? @{$self->{'info'}} : $self->{'info'}->[0];
}

# abs/relative adjustments
sub start    {  my $val = $_[0]->parent->reversed ? $_[0]->abs_end : $_[0]->abs_start; 
		return $val if $_[0]->abs;
		return $_[0]->abs2rel($val);
	      }
	
sub end    {  my $val = $_[0]->parent->reversed ? $_[0]->abs_start : $_[0]->abs_end; 
		return $val if $_[0]->abs;
		return $_[0]->abs2rel($val);
	      }

sub asString {
  my $self = shift;
  my $type = $self->type;
  my $name = _field(8,$self);
  ($name) = $name =~ /\"([^\"]+)\"/; # get rid of quote
  my $start = $self->start;
  my $end = $self->end;
  return "$type:$name/$start-$end";
#  return "$name:$type [$start-$end]";
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

# synthesize an artificial Ace object based on the tag
sub tag2ace {
    my $self = shift;
    my ($tag,@data) = @_;

    # Special cases, hardcoded in Ace GFF code...

    # for Notes we just return a text, no database associated
    return Ace::Object->new(Text=>$data[0]) if $tag eq 'Note';
    
    # for homols, we create the indicated Protein or Sequence object
    # then generate a bogus Homology object (for future compatability??)
    if ($tag eq 'Target') {
	my $db = $self->db;;
	my ($objname,$start,$end) = @data;
	my ($class,$name) = $objname =~ /^(\w+):(.+)/;
	return Ace::Sequence::Homol->new($db,$class,$name,$start,$end);
    }

    # General case:
    my $obj = Ace::Object->new($tag=>$data[0],$self->db);

    return $obj if defined $obj;

    # Last resort, return a Text
    return Ace::Object->new(Text=>$data[0]);
}

1;

__END__

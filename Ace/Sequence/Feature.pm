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
sub source_seq { $_[0]->parent; }
sub db     { return $_[0]->{'db'} ||= $_[0]->parent->source_seq->db; }
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
 
sub group  { $[0]->info; }
sub target { $[0]->info; }

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

=head1 NAME

Ace::Sequence::Feature - Examine Sequence Feature Tables

=head1 SYNOPSIS

    # open database connection and get an Ace::Object sequence
    use Ace::Sequence;

    # get a megabase from the middle of chromosome I
    $seq = Ace::Sequence->new(-name   => 'CHROMOSOME_I,
                              -db     => $db,
			      -offset => 3_000_000,
			      -length => 1_000_000);

    # get all the homologies (a list of Ace::Sequence::Feature objs)
    @homol = $seq->features('Similarity');

    # Get information about the first one
    $feature = $homol[0];
    $type    = $feature->type;
    $subtype = $feature->subtype;
    $start   = $feature->start;
    $end     = $feature->end;
    $score   = $feature->score;

    # Follow the target
    $target  = $feature->info;

    # print the target's start and end positions
    print $target->start,'-',$target->end, "\n";

=head1 DESCRIPTION

I<Ace::Sequence::Feature> is a subclass of L<Ace::Sequence::Feature>
specialized for returning information about particular features in a
GFF format feature table.

=head1  OBJECT CREATION

You will not ordinarily create an I<Ace::Sequence::Feature> object
directly.  Instead, objects will be created in response to a feature()
call to an I<Ace::Sequence> object.  If you wish to create an
I<Ace::Sequence::Feature> object directly, please consult the source
code for the I<new()> method.

=head1 OBJECT METHODS

Most methods are inherited from I<Ace::Sequence>.  The following
methods are also supported:

=over 4

=item seqname()

  $object = $feature->seqname;

Return the ACeDB Sequence object that this feature is attached to.
The return value is an I<Ace::Object> of the Sequence class.  This
corresponds to the first field of the GFF format and does not
necessarily correspond to the I<Ace::Sequence> object from which the
feature was obtained (use source_seq() for that).

=item source()

=item method()

=item subtype()

  $source = $feature->source;

These three methods are all synonyms for the same thing.  They return
the second field of the GFF format, called "source" in the
documentation.  This is usually the method or algorithm used to
predict the feature, such as "GeneFinder" or "tRNA" scan.  To avoid
ambiguity and enhance readability, the method() and subtype() synonyms
are also recognized.

=item feature()

=item type()

  $type = $feature->type;

These two methods are also synonyms.  They return the type of the
feature, such as "exon", "similarity" or "Predicted_gene".  In the GFF
documentation this is called the "feature" field.  For readability,
you can also use type() to fetch the field.

=item abs_start()

  $start = $feature->abs_start;

This method returns the absolute start of the feature within the
sequence segment indicated by seqname().  As in the I<Ace::Sequence>
method, use start() to obtain the start of the feature relative to its
source.

=item abs_start()

  $start = $feature->abs_start;

This method returns the start of the feature relative to the sequence
segment indicated by seqname().  As in the I<Ace::Sequence> method,
you will more usually use the inherited start() method to obtain the
start of the feature relative to its source sequence (the
I<Ace::Sequence> from which it was originally derived).

=item abs_end()

  $start = $feature->abs_end;

This method returns the end of the feature relative to the sequence
segment indicated by seqname().  As in the I<Ace::Sequence> method,
you will more usually use the inherited end() method to obtain the end
of the feature relative to the I<Ace::Sequence> from which it was
derived.

=item score()

  $score = $feature->score;

For features that are associated with a numeric score, such as
similarities, this returns that value.  For other features, this
method returns undef.

=item strand()

  $strand = $feature->strand;

Returns the strandedness of this feature, either "+" or "-".  For
features that are not stranded, returns undef.

=item reversed()

  $reversed = $feature->reversed;

Returns true if the feature is reversed relative to its source
sequence. 

=item frame()

  $frame = $feature->frame;

For features that have a frame, such as a predicted coding sequence,
returns the frame, either 0, 1 or 2.  For other features, returns undef.

=item group()

=item info()

=item target()

  $info = $feature->info;

These methods (synonyms for one another) return an Ace::Object
containing other information about the feature derived from the 8th
field of the GFF format, the so-called "group" field.  The type of the
Ace::Object is dependent on the nature of the feature.  The
possibilities are shown in the table below:

  Feature Type           Value of Group Field
  ------------            --------------------
  
  note                   A Text object containing the note.
  
  similarity             An Ace::Sequence::Homology object containing
                         the target and its start/stop positions.

  intron                 An Ace::Object containing the gene from 
  exon                   which the feature is derived.
  misc_feature

  other                  A Text object containing the group data.

=item asString()

  $label = $feature->asString;

Returns a human-readable identifier describing the nature of the
feature.  The format is:

 $type:$name/$start-$end

for example:

 exon:ZK154.3/1-67

This method is also called automatically when the object is treated in
a string context.

=back

=head1 SEE ALSO

L<Ace>, L<Ace::Object>, L<Ace::Sequence>,L<Ace::Sequence::Homol>,
L<Ace::Sequence::FeatureList>, L<GFF>

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1999, Lincoln D. Stein

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut



package Ace::Object::Wormbase;
use strict;
use Carp;
use Ace::Object;

# $Id: Wormbase.pm,v 1.2 2001/01/10 05:42:23 lstein Exp $
use vars '@ISA';
@ISA = 'Ace::Object';

# override the Locus method for backward compatibility with model shift
sub Locus {
  my $self = shift;
  return $self->SUPER::Locus(@_) unless $self->class eq 'Sequence';
  if (wantarray) {
    return ($self->Locus_genomic_seq,$self->Locus_other_seq);
  } else {
    return $self->Locus_genomic_seq || $self->Locus_other_seq;
  }
}

sub Sequence {
  my $self = shift;
  return $self->SUPER::Sequence(@_) unless $self->class eq 'Locus';
  if (wantarray) {
    return ($self->Genomic_sequence,$self->Other_sequence);
  } else {
    return $self->Genomic_sequence || $self->Other_sequence;
  }
}


1;

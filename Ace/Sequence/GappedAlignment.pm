package Ace::Sequence::GappedAlignment;

use strict;
use Ace;
use Ace::Sequence::Feature;
use vars '$AUTOLOAD';
use overload 
  '""' => 'asString',
  ;


# autoload delegates everything to the Sequence feature
sub AUTOLOAD {
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  my $self = shift;
  $self->{base}->$func_name(@_);
}

sub new {
  my $class = shift;
  my $segments = shift;

  # sort segments by position
  my @segs = sort {$a->{offset} <=> $b->{offset}} @$segments;
  my $offset = $segs[0]->{offset};
  my $len    = $segs[-1]->end - $segs[0]->start + 1;
  my $base = { %{$segs[0]} };
  $base->{length} = $len;
  bless $base,ref($segs[0]);
  return bless {
		base     => $base,
		segments => $segments,
	       },$class;
}

sub smapped { 1; }

sub asString {
  shift->{base}->info;
}

sub type {
  return 'GappedAlignment';
}

sub relative {
  my $self = shift;
  my $d = $self->{relative};
  $self->{relative} = shift if @_;
  $d;
}

sub segments {
  my $self = shift;
  return $self->{segments} ? @{$self->{segments}} : () unless $self->relative;
  # otherwise, we have to handle relative coordinates
  my $base   = $self->{base};
  my @e = map {Ace::Sequence->new(-refseq=>$base,-seq=>$_)} @{$self->{segments}};
  return $self->strand eq '-' ? reverse @e : @e;
}

1;

__END__

=head1 NAME

Ace::Sequence::GappedAlignment - Gapped alignment object

=head1 SYNOPSIS

    # open database connection and get an Ace::Sequence object
    use Ace::Sequence;

    # get a megabase from the middle of chromosome I
    $seq = Ace::Sequence->new(-name   => 'CHROMOSOME_I,
                              -db     => $db,
			      -offset => 3_000_000,
			      -length => 1_000_000);

    # get all the gapped alignments
    @alignments = $seq->alignments('EST_GENOME');

    # get the aligned segments from the first one
    @segs = $alignments[0]->segments;

    # get the position of the first aligned segment on the
    # source sequence:
    ($s_start,$s_end) = ($segs[0]->start,$segs[0]->end);

    # get the target position for the first aligned segment
    ($t_start,$t_end) = ($segs[0]->target->start,$segs[0]->target->end);

=head1 DESCRIPTION

Ace::Sequence::GappedAlignment is a subclass of
Ace::Sequence::Feature.  It inherits all the methods of
Ace::Sequence::Feature, but adds the ability to retrieve the positions
of the aligned segments.  Each segment is an Ace::Sequence::Feature,
from which you can retrieve the source and target coordinates.

=head1  OBJECT CREATION

You will not ordinarily create an I<Ace::Sequence::GappedAlignment>
object directly.  Instead, objects will be created in response to a
alignments() call to an I<Ace::Sequence> object.

=head1 OBJECT METHODS

Most methods are inherited from I<Ace::Sequence::Feature>.  The
following methods are also supported:

=over 4

=item segments()

  @segments = $gene->segments;

Return a list of Ace::Sequence::Feature objects corresponding to
similar segments.

=item relative()

  $relative = $gene->relative;
  $gene->relative(1);

This turns on and off relative coordinates.  By default, the exons and
intron features will be returned in the coordinate system used by the
gene.  If relative() is set to a true value, then coordinates will be
expressed as relative to the start of the gene.  The first exon will
(usually) be 1.

=head1 SEE ALSO

L<Ace>, L<Ace::Object>, L<Ace::Sequence>,L<Ace::Sequence::Homol>,
L<Ace::Sequence::Feature>, L<Ace::Sequence::FeatureList>, L<GFF>

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1999, Lincoln D. Stein

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut


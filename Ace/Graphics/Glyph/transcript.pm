package Ace::Graphics::Glyph::transcript;
# package to use for drawing transcripts

use strict;
use vars '@ISA';
@ISA = 'Ace::Graphics::Glyph';

use constant IMPLIED_INTRON_COLOR  => 'gray';
use constant ARROW => 4;

# override the left and right methods in order to
# provide extra room for arrows at the end
sub calculate_left {
  my $self = shift;
  my $val = $self->SUPER::calculate_left(@_);
  $val -= ARROW if $self->feature->strand < 0 && $val >= 4;
  $val;
}

sub calculate_right {
  my $self = shift;
  my $left = $self->left;
  my $val = $self->SUPER::calculate_right(@_);
  $val = $left + ARROW if $left + ARROW > $val;

  if ($self->option('label') && (my $description = $self->description)) {
    my $description_width = $self->font->width * length $self->description;
    $val = $left + $description_width if $left + $description_width > $val;
  }
  $val;
}

# override the bottom method in order to provide extra room for
# the label
sub calculate_height {
  my $self = shift;
  my $val = $self->SUPER::calculate_height(@_);
  $val += $self->labelheight if $self->option('label') && $self->description;
  $val;
}

# override draw method
sub draw {
  my $self = shift;

  # bail out if this isn't the right kind of feature
  return $self->SUPER::draw(@_) unless $self->feature->can('segments');

  # get parameters
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);
  my ($left,$top) = @_;

  my $implied_intron_color = $self->option('implied_intron_color') || IMPLIED_INTRON_COLOR;
  my $gray = $self->factory->translate($implied_intron_color);

  my @exons   = sort {$a->start<=>$b->start} $self->feature->segments;
  my @introns = $self->feature->introns if $self->feature->can('introns');

  # fill in missing introns
  my (%istart,@intron_boxes,@implied_introns,@exon_boxes);
  foreach (@introns) {
    my ($start,$stop) = ($_->start,$_->stop);
    ($start,$stop) = ($stop,$start) if $start > $stop;
    $istart{$start}++;
    push @intron_boxes,[$left+$self->map_pt($start),$left+$self->map_pt($stop)];
  }

  for (my $i=0; $i < @exons; $i++) {
    my ($start,$stop) = ($exons[$i]->start,$exons[$i]->stop);
    ($start,$stop) = ($stop,$start) if $start > $stop;
    push @exon_boxes,[$left+$self->map_pt($start),my $stop_pos = $left + $self->map_pt($stop)];

    next unless my $next_exon = $exons[$i+1];

    my $next_start = $next_exon->start < $next_exon->stop ?
      $next_exon->start : $next_exon->stop;

    my $next_start_pos = $left + $self->map_pt($next_start);
    # fudge boxes that are within two pixels of each other
    if ($next_start_pos - $stop_pos < 2) {
      $exon_boxes[-1][1] = $next_start_pos;

    } elsif ($next_exon && !$istart{$stop+1}) {
      push @implied_introns,[$stop_pos,$next_start_pos];
    }
}

  my $fg     = $self->fgcolor;
  my $fill   = $self->fillcolor;
  my $center  = ($y1 + $y2)/2;
  my $quarter = $y1 + ($y2-$y1)/4;

  # each intron becomes an angly thing
  foreach ([\@intron_boxes,$fg],[\@implied_introns,$gray]) {
    my ($i,$color) = @$_;

    for my $i (@$i) {
      if ($i->[1] - $i->[0] > 3) {  # room for the inverted "V"
	my $middle = $i->[0] + ($i->[1] - $i->[0])/2;
	$gd->line($i->[0],$center,$middle,$y1,$color);
	$gd->line($middle,$y1,$i->[1],$center,$color);
      } elsif ($i->[1]-$i->[0] > 1) { # no room, just connect
	$gd->line($i->[0],$quarter,$i->[1],$quarter,$color);
      }
    }
  }

  # each exon becomes a box
  for my $e (@exon_boxes) {
    my @rect = ($e->[0],$y1,$e->[1],$y2);
    $self->filled_box($gd,@rect);
  }

  my $draw_arrow = $self->option('draw_arrow');
  $draw_arrow = 1 unless defined $draw_arrow;

  if ($draw_arrow) {
    # draw little arrows to indicate direction of transcription
    # plus strand is to the right
    my $a2 = ARROW/2;
    my $s = $left + $self->map_pt($self->feature->end);
    if ($self->feature->strand > 0) {
      $gd->line($s,$center,$s + ARROW,$center,$fg);
      $gd->line($s+ARROW,$center,$s+$a2,$center-$a2,$fg);
      $gd->line($s+ARROW,$center,$s+$a2,$center+$a2,$fg);
    } else {
      $gd->line($s,$center,$s - ARROW,$center,$fg);
      $gd->line($s - ARROW,$center,$s-$a2,$center-$a2,$fg);
      $gd->line($s - ARROW,$center,$s-$a2,$center+$a2,$fg);
    }
  }

  # draw label
  if ($self->option('label')) {
    $self->draw_label($gd,@_);

    # draw description
    if (my $d = $self->description) {
      $gd->string($self->font,$x1,$y2,$d,$fill);
    }
  }

}

sub description {
  my $self = shift;
  my $t = $self->feature->info;
  return unless ref $t;

  my $id = $t->Brief_identification;
  my $comment = $t->Locus;
  $comment .= $comment ? " ($id)" : $id if $id;
  $comment;
}

1;

__END__

=head1 NAME

Ace::Graphics::Glyph::transcript - The "gene" glyph

=head1 SYNOPSIS

  See L<Ace::Graphics::Panel> and L<Ace::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws a series of filled rectangles connected by up-angled
connectors or "hats".  The rectangles indicate exons; the hats are
introns.  The direction of transcription is indicated by a small arrow
at the end of the glyph, rightward for the + strand.

The feature must respond to the exons() and optionally introns()
methods, or it will default to the generic display.  Implied introns
(not returned by the introns() method) are drawn in a contrasting
color to explicit introns.

=head2 OPTIONS

In addition to the common options, the following glyph-specific
option is recognized:

  Option                Description                    Default
  ------                -----------                    -------

  -implied_intron_color The color to use for gaps      gray
                        not returned by the introns()
                        method.

  -draw_arrow           Whether to draw arrowhead      true
                        indicating direction of
                        transcription.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Ace::Sequence>, L<Ace::Sequence::Feature>, L<Ace::Graphics::Panel>,
L<Ace::Graphics::Track>, L<Ace::Graphics::Glyph::anchored_arrow>,
L<Ace::Graphics::Glyph::arrow>,
L<Ace::Graphics::Glyph::box>,
L<Ace::Graphics::Glyph::primers>,
L<Ace::Graphics::Glyph::segments>,
L<Ace::Graphics::Glyph::toomany>,
L<Ace::Graphics::Glyph::transcript>,

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

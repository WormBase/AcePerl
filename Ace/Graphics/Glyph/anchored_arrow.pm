package Ace::Graphics::Glyph::anchored_arrow;
# package to use for drawing an arrow

use strict;
use vars '@ISA';
@ISA = 'Ace::Graphics::Glyph';

# override draw method
sub draw {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  my $fg = $self->fgcolor;
  my $a2 = ($y2-$y1)/2;
  my $center = $y1+$a2;

  $gd->line($x1,$center,$x2,$center,$fg);

  if ($self->feature->start < $self->offset) {  # off left end
    if ($x2 > $a2) {
      $gd->line($x1,$center,$x1+$a2,$center-$a2,$fg);  # arrowhead
      $gd->line($x1,$center,$x1+$a2,$center+$a2,$fg);
    }
  } else {
    $gd->line($x1,$center-$a2,$x1,$center+$a2,$fg);  # tick/base
  }

  if ($self->feature->end > $self->offset + $self->length) {# off right end
    if ($x1 < $x2-$a2-1) {
      $gd->line($x2,$center,$x2-$a2,$center+$a2,$fg);  # arrowhead
      $gd->line($x2,$center,$x2-$a2,$center-$a2,$fg);
    }
  } else {
    # problems occur right at the very end because of GD confusion
    $x2-- if $self->feature->end == $self->offset + $self->length;
    $gd->line($x2,$center-$a2,$x2,$center+$a2,$fg);  # tick/base
  }

  $self->draw_ticks($gd,$center,$a2,@_) if $self->option('ticks');

  # add a label if requested
  $self->draw_label($gd,@_) if $self->option('label');
}

sub draw_label {
  my $self = shift;
  my ($gd,$left,$top) = @_;
  my $label = $self->label or return;
  my $start = $self->left + ($self->right - $self->left - length($label) * $self->font->width)/2;
  $gd->string($self->font,$left + $start,$top + $self->top,$label,$self->fontcolor);
}

sub draw_ticks {
  my $self  = shift;
  my ($gd,$center,$a2,$left,$top) = @_;

  my $scale = $self->scale;
  my $fg = $self->fgcolor;

  # figure out tick mark scale
  # we want no more than 1 tick mark every 30 pixels
  # and enough room for the labels
  my $font = $self->font;
  my $width = $font->width;
  my $font_color = $self->fontcolor;

  my $relative = $self->option('relative_coords');
  my $start    = $relative ? 1 : $self->start;
  my $stop     = $start + $self->length -1;

  my $interval = 1;
  my $mindist =  30;
  my $widest = 5 + (length($stop) * $width);
  $mindist = $widest if $widest > $mindist;

  while (1) {
    my $pixels = $interval * $scale;
    last if $pixels >= $mindist;
    $interval *= 10;
  }

  my $first_tick = $interval * int(0.5 + $start/$interval);

  for (my $i = $first_tick; $i < $stop; $i += $interval) {
    my $tickpos = $left + $self->map_pt(($i-1)+$self->start);
    $gd->line($tickpos,$center-$a2,$tickpos,$center+$a2,$fg);
    my $middle = $tickpos - (length($i) * $width)/2;
    $gd->string($font,$middle,$center+$a2-1,$i,$font_color);
  }

  if ($self->option('tick') >= 2) {
    my $a4 = $self->SUPER::height/4;
    for (my $i = $start+$interval/10; $i < $stop; $i += $interval/10) {
      my $tickpos = $left + $self->map_pt(($i-1)+$self->start);
      $gd->line($tickpos,$center-$a4,$tickpos,$center+$a4,$fg);
    }
  }
}



1;

__END__

=head1 NAME

Ace::Graphics::Glyph::anchored_arrow - The "anchored_arrow" glyph

=head1 SYNOPSIS

  See L<Ace::Graphics::Panel> and L<Ace::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws an arrowhead which is anchored at one or both ends
(has a vertical base) or has one or more arrowheads.  The arrowheads
indicate that the feature does not end at the edge of the picture, but
continues.  For example:

    |-----------------------------|          both ends in picture
 <----------------------|                    left end off picture
         |---------------------------->      right end off picture
 <------------------------------------>      both ends off picture


=head2 OPTIONS

No additional options are recognized.
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

package Ace::Graphics::Glyph::arrow;
# package to use for drawing an arrow

use strict;
use vars '@ISA';
@ISA = 'Ace::Graphics::Glyph';

sub bottom {
  my $self = shift;
  my $val = $self->SUPER::bottom(@_);
  $val += $self->font->height if $self->option('tick');
  $val;
}

# override draw method
sub draw {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  my $fg = $self->fgcolor;
  my $a2 = $self->SUPER::height/2;
  my $center = $y1+$a2;

  $gd->line($x1,$center,$x2,$center,$fg);
  $gd->line($x1,$center,$x1+$a2,$center-$a2,$fg);
  $gd->line($x1,$center,$x1+$a2,$center+$a2,$fg);
  $gd->line($x2,$center,$x2-$a2,$center+$a2,$fg);
  $gd->line($x2,$center,$x2-$a2,$center-$a2,$fg);

  # turn on ticks
  if ($self->option('tick')) {
    my $scale = $self->scale;

    # figure out tick mark scale
    # we want no more than 1 tick mark every 30 pixels
    # and enough room for the labels
    my $font = $self->font;
    my $width = $font->width;

    my $interval = 1;
    my $mindist =  30;
    my $widest = 5 + (length($self->end) * $width);
    $mindist = $widest if $widest > $mindist;

    while (1) {
      my $pixels = $interval * $scale;
      last if $pixels >= $mindist;
      $interval *= 10;
    }

    my $first_tick = $interval * int(1 + $self->start/$interval);

    for (my $i = $first_tick; $i < $self->end; $i += $interval) {
      my $tickpos = $self->map_pt($i);
      $gd->line($tickpos,$center-$a2,$tickpos,$center+$a2,$fg);
      my $middle = $tickpos - (length($i) * $width)/2;
      $gd->string($font,$middle,$center+$a2-1,$i,$fg);
    }

    if ($self->option('tick') >= 2) {
      my $a4 = $self->SUPER::height/4;
      for (my $i = $self->start+$interval/10; $i < $self->end; $i += $interval/10) {
	my $tickpos = $self->map_pt($i);
	$gd->line($tickpos,$center-$a4,$tickpos,$center+$a4,$fg);
      }
    }
  }

}

1;

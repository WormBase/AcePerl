package Ace::Graphics::Glyph::primers;
# package to use for drawing something that looks like
# primer pairs.

use strict;
use vars '@ISA';
@ISA = 'Ace::Graphics::Glyph';

use constant HEIGHT => 4;

# we do not need the default amount of room
sub _height {
  my $self = shift;
  return $self->option('label') ? HEIGHT + $self->labelheight + 2 : HEIGHT;
}

# override draw method
sub draw {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  my $fg = $self->fgcolor;
  my $a2 = HEIGHT/2;
  my $center = $y1 + $a2;

  # just draw us as a solid line -- very simple
  if ($x2-$x1 < HEIGHT*2) {
    $gd->line($x1,$center,$x2,$center,$fg);
    return;
  }

  # otherwise draw two pairs of arrows
  # -->   <--
  $gd->line($x1,$center,$x1 + HEIGHT,$center,$fg);
  $gd->line($x1 + HEIGHT,$center,$x1 + HEIGHT - $a2,$center-$a2,$fg);
  $gd->line($x1 + HEIGHT,$center,$x1 + HEIGHT - $a2,$center+$a2,$fg);

  $gd->line($x2,$center,$x2 - HEIGHT,$center,$fg);
  $gd->line($x2 - HEIGHT,$center,$x2 - HEIGHT + $a2,$center+$a2,$fg);
  $gd->line($x2 - HEIGHT,$center,$x2 - HEIGHT + $a2,$center-$a2,$fg);

  # connect the dots if requested
  if ($self->option('connect')) {
    my $c = $self->color('connector');
    $gd->line($x1 + HEIGHT + 2,$center,$x2 - HEIGHT - 2,$center,$c);
  }

  # add a label if requested
  $self->draw_label($gd,@_) if $self->option('label');

}


1;

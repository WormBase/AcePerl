package Ace::Graphics::Glyph::ex;
# DAS-compatible package to use for drawing a box

use strict;
use vars '@ISA';
@ISA = 'Ace::Graphics::Glyph';

sub draw {
  my $self = shift;
#  $self->SUPER::draw(@_);
  my $gd = shift;
  my $fg = $self->fgcolor;

  # now draw a cross
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);
  my $fg = $self->fgcolor;
  $gd->line($x1,$y1,$x2,$y2,$fg);
  $gd->line($x1,$y2,$x2,$y1,$fg);

  $self->draw_label($gd,@_) if $self->option('label');
}

1;

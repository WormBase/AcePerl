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

  # add a label if requested
  $self->draw_label($gd,@_) if $self->option('label');
}

sub draw_label {
  my $self = shift;
  my ($gd,$left,$top) = @_;
  my $label = $self->label or return;
  my $start = $self->left + ($self->right - $self->left - length($label) * $self->font->width)/2;
  $gd->string($self->font,$left + $start,$top + $self->top,$label,$self->fgcolor);
}

1;

package Ace::Graphics::Glyph;

use strict;
use GD;

# simple glyph class
# args:  -feature => $feature_object
# args:  -factory => $factory_object
sub new {
  my $class = shift;
  my %arg = @_;
  my $feature = $arg{-feature};
  my ($start,$end) = ($feature->start,$feature->end);
  ($start,$end) = ($end,$start) if $start > $end;
  return bless { 
		@_,
		top   => 0,
		left  => 0,
		start => $start,
		end   => $end
	       },$class;
}

# delegates
# any of these can be overridden safely
sub feature   {  shift->{-feature}            }
sub fgcolor   {  shift->{-factory}->fgcolor   }
sub bgcolor   {  shift->{-factory}->bgcolor   }
sub fillcolor {  shift->{-factory}->fillcolor }
sub scale     {  shift->{-factory}->scale     }
sub font      {  shift->{-factory}->font      }
sub height    {  shift->{-factory}->height    }
sub start     {  shift->{start}               }
sub end       {  shift->{end}                 }

# change our offset
sub move {
  my $self = shift;
  my ($dx,$dy) = @_;
  $self->{left} += $dx;
  $self->{top}  += $dy;
}

# positions, in pixel coordinates
sub top    { shift->{top}                 }
sub bottom { my $s = shift; $s->top + $s->height   }
sub left {
  my $self = shift;
  my $val = $self->{left} + $self->scale * ($self->{start} - 1);
  return $val > 0 ? $val : 0;
}
sub right {
  my $self = shift;
  my $val = $self->{left} + $self->scale * ($self->{end} - 1);
  return $val > 0 ? $val : 0;
}

# return array containing the left,top,right,bottom
sub box {
  my $self = shift;
  return ($self->left,$self->top,$self->right,$self->bottom);
}

# draw the thing onto a canvas
# this definitely gets overridden
sub draw {
  my $self = shift;
  my $gd   = shift;
  my ($left,$top) = @_;
  my $x1  = $self->left   + $left;
  my $y1  = $self->top    + $top;
  my $x2  = $self->right  + $left;
  my $y2  = $self->bottom + $top;

  $x2 = $x1 if $x2-$x1 < 1;

  # for now, just draw a box
  $gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);

  # and fill it
  if ( ($x2-$x1) > 2 and ($y2-$y1) > 2 ) {
    my $h = ($x2+$x1)/2;
    my $v = ($y2+$y1)/2;
    $gd->fill($h,$v,$self->fillcolor);
  }

}

1;

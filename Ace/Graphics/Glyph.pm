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
		right => 0,
		start => $start,
		end   => $end
	       },$class;
}

# delegates
# any of these can be overridden safely
sub factory   {  shift->{-factory}            }
sub feature   {  shift->{-feature}            }

sub fgcolor   {  shift->factory->fgcolor   }
sub bgcolor   {  shift->factory->bgcolor   }
sub fillcolor {  shift->factory->fillcolor }
sub scale     {  shift->factory->scale     }
sub width     {  shift->factory->width     }
sub font      {  shift->factory->font      }
sub option    {  shift->factory->option(@_) }
sub color     {  
  my $self    = shift;
  my $factory = $self->factory;
  my $color   = $factory->option(@_) or return $self->fgcolor;
  $factory->translate($color);
}

sub start     { shift->{start}                 }
sub end       { shift->{end}                   }
sub offset    { shift->factory->offset      }
sub length    { shift->factory->length      }

# this is a very important routine that dictates the
# height of the bounding box.  We start with the height
# dictated by the factory, and then adjust if needed
sub height   {
  my $self = shift;
  return $self->{cache_height} if defined $self->{cache_height};
  return $self->{cache_height} = $self->_height;
}

sub _height {
  my $self = shift;
  my $val = $self->factory->height;
  $val += $self->labelheight if $self->option('label');
  $val;
}

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
  return $self->{cache_left} if defined $self->{cache_left};
  $self->{cache_left} = $self->_left;
}
sub right {
  my $self = shift;
  return $self->{cache_right} if defined $self->{cache_right};
  return $self->{cache_right} = $self->_right;
}

sub _left {
  my $self = shift;
  my $val = $self->{left} + $self->map_pt($self->{start} - 1);
  $val > 0 ? $val : 0;
}

sub _right {
  my $self = shift;
  my $val = $self->{left} + $self->map_pt($self->{end} - 1);
  $val = 0 if $val < 0;
  $val = $self->width if $val > $self->width;
  if ($self->option('label') && (my $label = $self->label)) {
    my $left = $self->left;
    my $label_width = $self->font->width * CORE::length $label;
    my $label_end   = $left + $label_width;
    $val = $label_end if $label_end > $val;
  }
  $val;
}

sub map_pt {
  my $self = shift;
  my $point = shift;
  $point -= $self->offset;
  my $val = $self->{left} + $self->scale * $point;
  my $right = $self->{left} + $self->width;
  $val = 0 if $val < 0;
  $val = $self->width if $right && $val > $right;
  return int($val+0.5);
}

sub labelheight {
  my $self = shift;
  return $self->{labelheight} ||= $self->font->height;
}

sub label {
  shift->feature->info;
}

# return array containing the left,top,right,bottom
sub box {
  my $self = shift;
  return ($self->left,$self->top,$self->right,$self->bottom);
}

# these are the sequence boundaries, exclusive of labels and doodads
sub calculate_boundaries {
  my $self = shift;
  my ($left,$top) = @_;

  my $x1 = $left + $self->{left} + $self->map_pt($self->{start} - 1);
  $x1 = 0 if $x1 < 0;

  my $x2 = $left + $self->{left} + $self->map_pt($self->{end} - 1);
  $x2 = 0 if $x2 < 0;

  my $y1 = $top + $self->{top};
  $y1 += $self->labelheight if $self->option('label');
  my $y2 = $y1 + $self->factory->height;

  $x2 = $x1 if $x2-$x1 < 1;
  $y2 = $y1 if $y2-$y1 < 1;

  return ($x1,$y1,$x2,$y2);
}

sub filled_box {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = @_;

  # draw a box
  $gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);

  # and fill it
  $self->fill($gd,$x1,$y1,$x2,$y2);

  # if the left end is off the end, then cover over
  # the leftmost line
  my ($width) = $gd->getBounds;
  $gd->line($x1,$y1,$x1,$y2,$self->fillcolor)
    if $x1 <= 0;

  $gd->line($x2,$y1,$x2,$y2,$self->fillcolor)
    if $x2 >= $width;
}

sub fill {
  my $self = shift;
  my $gd   = shift;
  my ($x1,$y1,$x2,$y2) = @_;
  if ( ($x2-$x1) >= 2 && ($y2-$y1) >= 2 ) {
    $gd->fill($x1+1,$y1+1,$self->fillcolor);
  }
}

# draw the thing onto a canvas
# this definitely gets overridden
sub draw {
  my $self = shift;
  my $gd   = shift;
  my ($left,$top) = @_;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries($left,$top);

  # for nice thin lines
  $x2 = $x1 if $x2-$x1 < 1;

  # for now, just draw a box
#  $gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);

  # and fill it
#  $self->fill($gd,$x1,$y1,$x2,$y2);

  $gd->filled_box($gd,$x1,$y1,$x2,$y2);

  # add a label if requested
  $self->draw_label($gd,@_) if $self->option('label');
}

sub draw_label {
  my $self = shift;
  my ($gd,$left,$top) = @_;
  my $label = $self->label or return;
  $gd->string($self->font,$left + $self->left,$top + $self->top,$label,$self->fgcolor);
}

1;

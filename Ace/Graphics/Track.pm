package Ace::Graphics::Track;
# This embodies the logic for drawing a single track of features.
# Features are of uniform style and are controlled by descendents of
# the Ace::Graphics::Glyph class (eek!).

use Ace::Sequence;
use Ace::Graphics::GlyphFactory;
use GD;  # maybe
use Carp 'croak';
use vars '$AUTOLOAD';
use strict;

sub AUTOLOAD {
  my $self = shift;
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  $self->factory->$func_name(@_);
}

# Pass a list of Ace::Sequence::Feature objects, and a glyph name
sub new {
  my $class = shift;
  my ($objects,$glyph_factory) = @_;
  $glyph_factory ||= $class->default_factory;
  return bless {
		features => $objects,        # list of Ace::Sequence::Feature objects
		factory  => $glyph_factory,  # the glyph class associated with this track
		bump     => 1,               # bump by default
		glyphs   => undef,           # list of glyphs
	       },$class;
}

# control bump direction:
#    +1   => bump downward
#    -1   => bump upward
#     0   => no bump
sub bump {
  my $self = shift;
  my $g = $self->{bump};
  $self->{bump} = shift if @_;
  $g;
}

# add a feature to the list
sub add_feature {
  my $self = shift;
  my $feature = shift;
  push @{$self->{features}},$feature;
}

# delegate lineheight to the glyph
sub lineheight {
  shift->{factory}->height(@_);
}

# the scale is horizontal, measured in pixels/bp
sub scale {
  my $self = shift;
  my $g = $self->{scale};
  $self->{scale} = shift if @_;
  $g;
}

# set scale by a segment
sub scale_to_segment {
  my $self = shift;
  my ($segment,$desired_width) = @_;
  $desired_width ||= 512;
  $self->scale($desired_width/$segment->length);
}

# return the glyph class
sub factory {
  my $self = shift;
  my $g = $self->{factory};
  $self->{factory} = shift if @_;
  $g;
}

# return boxes for each of the glyphs
# will be an array of four-element [$feature,l,t,r,b] arrays
sub boxes {
  my $self = shift;
  my ($top,$left) = @_;
  $top  += 0; $left += 0;
  my @result;

  my $glyphs = $self->layout;
  for my $g (@$glyphs) {
    my ($l,$t,$r,$b) = $g->box;
    push @result,[$g->feature,$left+$l,$top+$t,$left+$r,$top+$b];
  }

  return \@result;
}

# draw glyphs onto a GD object at the indicated position
sub draw {
  my $self = shift;
  my ($gd,$left,$top) = @_;
  $top  += 0;  $left += 0;

  my $glyphs = $self->layout;  
  $_->draw($gd,$left,$top) foreach @$glyphs;
}

# lay out -- this uses the infamous bump algorithm
sub layout {
  my $self = shift;
  my $force = shift || 0;
  return $self->{glyphs} if $self->{glyphs} and !$force;
  
  my $f = $self->{features};
  my $factory = $self->factory;
  $factory->scale($self->scale);  # set the horizontal scale

  # create glyphs and sort them horizontally
  my @glyphs = sort {$a->start <=> $b->start } map { $factory->glyph($_) } @$f;

  # run the bumper
  $self->_bump(\@glyphs) if $self->bump;

  # reverse coordinates for -1 bumping
  if ($self->bump < 0) {
    my $height = $self->height;
    $_->move(0,$height) foreach @glyphs;  #offset so that topmost is 0
  }

  return $self->{glyphs} = \@glyphs;
}

# bumper - glyphs already sorted left to right
sub _bump {
  my $self   = shift;
  my $glyphs = shift;
  my $bump_direction = $self->bump;  # +1 means bump down, -1 means bump up

  my %occupied;
  for my $g (@$glyphs) {
    my $pos = 0;
    for my $y (sort {$a<=>$b} keys %occupied) {
      my $previous = $occupied{$y};
      last if $previous->right + 2 < $g->left;          # no collision at this position
      $pos += $bump_direction * $previous->height + 2;  # collision, so bump
    }
    $occupied{$pos} = $g;                           # remember where we are
    $g->move(0,$bump_direction > 0 ? $pos : $pos-$g->height);
  }
}

# return list of glyphs -- only after they are laid out
sub glyphs { shift->{glyphs} }

# height is determined by the layout, and cannot be externally controlled
sub height {
  my $self = shift;
  $self->layout;
  my $glyphs = $self->{glyphs} or croak "Can't lay out";
  my @sorted = sort { $a->top <=> $b->top } @$glyphs;
  return $sorted[-1]->bottom - $sorted[0]->top;
}

sub default_factory { 
  Ace::Graphics::GlyphFactory->new;
}


1;

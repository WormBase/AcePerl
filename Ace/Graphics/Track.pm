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
  my ($objects,$glyph,@options) = @_;
  my $glyph_factory = $class->make_factory($glyph,@options);
  return bless {
		features => $objects,                    # list of Ace::Sequence::Feature objects
		factory  => $glyph_factory,              # the glyph class associated with this track
		bump     => 1,                           # bump by default
		glyphs   => undef,                       # list of glyphs
	       },$class;
}

# control bump direction:
#    +1   => bump downward
#    -1   => bump upward
#     0   => no bump
sub bump {
  my $self = shift;
  $self->factory->option('bump',@_);
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

sub width {
  my $self = shift;
  my $g = $self->{width};
  $self->{width} = shift if @_;
  $g;
}

# set scale by a segment
sub scale_to_segment {
  my $self = shift;
  my ($segment,$desired_width) = @_;
  $self->set_scale($segment->length,$desired_width);
}

sub set_scale {
  my $self = shift;
  my ($bp,$desired_width) = @_;
  $desired_width ||= 512;
  $self->scale($desired_width/$bp);
  $self->width($desired_width);
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
  my ($left,$top) = @_;
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
  return $self->{glyphs} if $self->{glyphs} && !$force;
  
  my $f = $self->{features};
  my $factory = $self->factory;
  $factory->scale($self->scale);  # set the horizontal scale
  $factory->width($self->width);

  # create glyphs and sort them horizontally
  my @glyphs = sort {$a->start <=> $b->start } map { $factory->glyph($_) } @$f;
  return $self->{glyphs} = [] if !@glyphs;

  # run the bumper
  $self->_bump(\@glyphs) if $self->bump;

  # If -1 bumping was allowed, then normalize so that the top glyph is at zero
  my ($topmost) = sort {$a->top <=> $b->top} @glyphs;
  my $offset = 0 - $topmost->top;
  $_->move(0,$offset) foreach @glyphs;

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
    for my $y (sort {$bump_direction * ($a <=> $b)} keys %occupied) {
      my $previous = $occupied{$y};
      last if $previous->right + 2 < $g->left;          # no collision at this position
      if ($bump_direction > 0) {
	$pos += $previous->height + 2;                    # collision, so bump
      } else {
	$pos -= $g->height + 2;
      }
    }
    $occupied{$pos} = $g;                           # remember where we are
    $g->move(0,$pos);
  }
}

# return list of glyphs -- only after they are laid out
sub glyphs { shift->{glyphs} }

# height is determined by the layout, and cannot be externally controlled
sub height {
  my $self = shift;
  $self->layout;
  my $glyphs = $self->{glyphs} or croak "Can't lay out";
  return 0 unless @$glyphs;

  my ($topmost)    = sort { $a->top    <=> $b->top }    @$glyphs;
  my ($bottommost) = sort { $b->bottom <=> $a->bottom } @$glyphs;
  return $bottommost->bottom - $topmost->top;
}

sub make_factory { 
  my ($class,$type,@options) = @_;
  Ace::Graphics::GlyphFactory->new($type,@options);
}


1;

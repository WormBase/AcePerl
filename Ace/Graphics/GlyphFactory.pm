package Ace::Graphics::GlyphFactory;
# parameters for creating sequence glyphs of various sorts
# you *do* like glyphs, don't you?

use strict;
use GD;

sub new {
  my $class = shift;
  my $glyphclass = 'Ace::Graphics::Glyph';
  if (my $subtype = shift) {
    $glyphclass .= "::$subtype";
  }
  eval "require $glyphclass" or return;
  return bless {
		glyphclass => $glyphclass,
		font       => gdSmallFont,
		bgcolor    => 0,
		fgcolor    => 1,
		fillcolor  => 2,
		scale      => 1,   # 1 pixel per kb
		height     => 10,  # 10 pixels high
	       },$class;
}

# set the scale for glyphs we create
sub scale {
  my $self = shift;
  my $g = $self->{scale};
  $self->{scale} = shift if @_;
  $g;
}

# font to draw with
sub font {
  my $self = shift;
  my $g = $self->{font};
  $self->{font} = shift if @_;
  $g;
}

# set the height for glyphs we create
sub height {
  my $self = shift;
  my $g = $self->{height};
  $self->{height} = shift if @_;
  $g;
}

# set the foreground and background colors
# expressed as GD color indices
sub fgcolor {
  my $self = shift;
  my $g = $self->{fgcolor};
  $self->{fgcolor} = shift if @_;
  $g;
}

sub bgcolor {
  my $self = shift;
  my $g = $self->{bgcolor};
  $self->{bgcolor} = shift if @_;
  $g;
}

sub fillcolor {
  my $self = shift;
  my $g = $self->{fillcolor};
  $self->{fillcolor} = shift if @_;
  $g;
}

# create a new glyph from configuration
sub glyph {
  my $self    = shift;
  my $feature = shift;
  return $self->{glyphclass}->new(-feature => $feature,
				  -factory => $self);
}

1;

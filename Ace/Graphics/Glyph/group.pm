package Ace::Graphics::Glyph::group;
# a group of glyphs that move in a coordinated fashion
# currently they are always on the same vertical level (no bumping)

use strict;
use vars '@ISA';
use GD;
use Carp 'croak';

@ISA = 'Ace::Graphics::Glyph';

# override new() to accept an array ref for -feature
# the ref is not a set of features, but a set of other glyphs!
sub new {
  my $class = shift;
  my %arg = @_;
  my $parts = $arg{-feature};
  croak('Usage: Ace::Graphics::Glyph::group->new(-features=>$glypharrayref,-factory=>$factory)')
    unless ref $parts eq 'ARRAY';

  # sort parts horizontally
  my @sorted = sort { $a->left   <=> $b->left } @$parts;
  my $leftmost  = $sorted[0];
  my $rightmost = (sort { $a->right  <=> $b->right  } @$parts)[-1];
  my $tallest   = (sort { $a->height <=> $b->height } @$parts)[-1];

  return bless {
		@_,
		top      => 0,
		left     => 0,
		right    => 0,
		leftmost => $leftmost,
		rightmost => $rightmost,
		tallest   => $tallest,
		members   => \@sorted,
	       },$class;
}

sub members {
  my $self = shift;
  my $m = $self->{members} or return;
  return @$m;
}

sub move {
  my $self = shift;
  $self->SUPER::move(@_);
  $_->move(@_) foreach $self->members;
}

sub left  {  shift->{leftmost}->left   }
sub right {  shift->{rightmost}->right }

sub height {
  my $self = shift;
  return $self->{tallest}->height;
}

# override draw method - draw individual subparts
sub draw {
  my $self = shift;
  my $gd = shift;
  my ($left,$top) = @_;

  # bail out if this isn't the right kind of feature
  my @parts = $self->members;

  # three pixels of black, three pixels of transparent
  my $black = 1;
  my ($x1,$y1,$x2,$y2) = $parts[0]->calculate_boundaries($left,$top);
  my $center = ($y2 + $y1)/2;

  $gd->setStyle($black,$black,gdTransparent,gdTransparent,);
  for (my $i=0;$i<@parts-1;$i++) {
    my $start = ($parts[$i]->box)[2];
    my $end   = ($parts[$i+1]->box)[0];
    next unless ($end - $start) > 6;
    $gd->line($left + $start,$center,$left + $end,$center,gdStyled);
  }

}

1;

package Ace::Graphics::Panel;
# This embodies the logic for drawing multiple tracks.

use Ace::Graphics::Track;
use GD;
use Carp 'croak';
use strict;

# package global
my %COLORS;

# Create a new panel of a given width and height, and add lists of features
# one by one
sub new {
  my $class = shift;
  my %options = @_;

  $class->read_colors() unless %COLORS;

  my $length = $options{-length} || 0;
  my $offset = $options{-offset} || 0;

  $length   ||= $options{-segment}->length  if $options{-segment};
  $offset   ||= $options{-segment}->start-1 if $options{-segment};

  return bless {
		tracks => [],
		width  => $options{-width} || 600,
		pad_top    => $options{-pad_top},
		pad_bottom => $options{-pad_bottom},
		length => $length,
		offset => $offset,
		height => 0, # AUTO
		spacing => 5,
	       },$class;
}

sub width {
  my $self = shift;
  my $d = $self->{width};
  $self->{width} = shift if @_;
  $d;
}

sub spacing {
  my $self = shift;
  my $d = $self->{spacing};
  $self->{spacing} = shift if @_;
  $d;
}

sub length {
  my $self = shift;
  my $d = $self->{length};
  if (@_) {
    my $l = shift;
    $l = $l->length if ref($l) && $l->can('length');
    $self->{length} = $l;
  }
  $d;
}

sub pad_top {
  my $self = shift;
  my $d = $self->{pad_top};
  $self->{pad_top} = shift if @_;
  $d || 0;
}

sub pad_bottom {
  my $self = shift;
  my $d = $self->{pad_bottom};
  $self->{pad_bottom} = shift if @_;
  $d || 0;
}

sub add_track {
  my $self = shift;
  my ($features,$glyph_type,@options) = @_;

  # if the first argument is a string, then assume features is empty
  if ( !ref($features) ) {
    unshift @options,$glyph_type;
    $glyph_type = $features;
    $features = [];
  }

  # if glyph_type begins with a dash, then this is the beginning
  # of the options
  if ($glyph_type =~ /^-/) {
    unshift @options,$glyph_type;
    undef $glyph_type;
  }
  unshift @options,'offset' => $self->{offset} if defined $self->{offset};
  unshift @options,'length' => $self->{length} if defined $self->{length};

  $features = [$features] unless ref $features eq 'ARRAY';
  my $track  = Ace::Graphics::Track->new($features,$glyph_type,@options);
  $track->set_scale($self->length,$self->width);
  push @{$self->{tracks}},$track;
  return $track;
}

sub height {
  my $self = shift;
  my $height = 0;
  my $spacing = $self->spacing;
  $height += $_->height + $spacing foreach @{$self->{tracks}};
  $height + $self->pad_top + $self->pad_bottom;
}

sub gd {
  my $self = shift;

  return $self->{gd} if $self->{gd};

  my $width  = $self->width;
  my $height = $self->height;
  my $gd = GD::Image->new($width,$height);
  my %translation_table;
  for my $name ('white','black',keys %COLORS) {
    my $idx = $gd->colorAllocate(@{$COLORS{$name}});
    $translation_table{$name} = $idx;
  }

  my $offset = $self->pad_top;
  for my $track (@{$self->{tracks}}) {
    $track->color_translations(\%translation_table);
    $track->draw($gd,0,$offset);
    $offset += $track->height + $self->spacing;
  }

  return $self->{gd} = $gd;
}

sub draw {
  my $gd = shift->gd;
  $gd->png;
}

sub boxes {
  my $self = shift;
  my @boxes;
  my $offset = 0;
  my $pad = $self->pad_top;
  for my $track (@{$self->{tracks}}) {
    my $boxes = $track->boxes(0,$offset+$pad);
    push @boxes,@$boxes;
    $offset += $track->height + $self->spacing;
  }
  return \@boxes;
}

sub read_colors {
  my $class = shift;
  while (<DATA>) {
    chomp;
    my ($name,$r,$g,$b) = split /\s+/;
    $COLORS{$name} = [hex $r,hex $g,hex $b];
  }
}


1;

__DATA__
white                FF           FF            FF
black                00           00            00
aliceblue            F0           F8            FF
antiquewhite         FA           EB            D7
aqua                 00           FF            FF
aquamarine           7F           FF            D4
azure                F0           FF            FF
beige                F5           F5            DC
bisque               FF           E4            C4
blanchedalmond       FF           EB            CD
blue                 00           00            FF
blueviolet           8A           2B            E2
brown                A5           2A            2A
burlywood            DE           B8            87
cadetblue            5F           9E            A0
chartreuse           7F           FF            00
chocolate            D2           69            1E
coral                FF           7F            50
cornflowerblue       64           95            ED
cornsilk             FF           F8            DC
crimson              DC           14            3C
cyan                 00           FF            FF
darkblue             00           00            8B
darkcyan             00           8B            8B
darkgoldenrod        B8           86            0B
darkgray             A9           A9            A9
darkgreen            00           64            00
darkkhaki            BD           B7            6B
darkmagenta          8B           00            8B
darkolivegreen       55           6B            2F
darkorange           FF           8C            00
darkorchid           99           32            CC
darkred              8B           00            00
darksalmon           E9           96            7A
darkseagreen         8F           BC            8F
darkslateblue        48           3D            8B
darkslategray        2F           4F            4F
darkturquoise        00           CE            D1
darkviolet           94           00            D3
deeppink             FF           14            100
deepskyblue          00           BF            FF
dimgray              69           69            69
dodgerblue           1E           90            FF
firebrick            B2           22            22
floralwhite          FF           FA            F0
forestgreen          22           8B            22
fuchsia              FF           00            FF
gainsboro            DC           DC            DC
ghostwhite           F8           F8            FF
gold                 FF           D7            00
goldenrod            DA           A5            20
gray                 80           80            80
green                00           80            00
greenyellow          AD           FF            2F
honeydew             F0           FF            F0
hotpink              FF           69            B4
indianred            CD           5C            5C
indigo               4B           00            82
ivory                FF           FF            F0
khaki                F0           E6            8C
lavender             E6           E6            FA
lavenderblush        FF           F0            F5
lawngreen            7C           FC            00
lemonchiffon         FF           FA            CD
lightblue            AD           D8            E6
lightcoral           F0           80            80
lightcyan            E0           FF            FF
lightgoldenrodyellow FA           FA            D2
lightgreen           90           EE            90
lightgrey            D3           D3            D3
lightpink            FF           B6            C1
lightsalmon          FF           A0            7A
lightseagreen        20           B2            AA
lightskyblue         87           CE            FA
lightslategray       77           88            99
lightsteelblue       B0           C4            DE
lightyellow          FF           FF            E0
lime                 00           FF            00
limegreen            32           CD            32
linen                FA           F0            E6
magenta              FF           00            FF
maroon               80           00            00
mediumaquamarine     66           CD            AA
mediumblue           00           00            CD
mediumorchid         BA           55            D3
mediumpurple         100          70            DB
mediumseagreen       3C           B3            71
mediumslateblue      7B           68            EE
mediumspringgreen    00           FA            9A
mediumturquoise      48           D1            CC
mediumvioletred      C7           15            85
midnightblue         19           19            70
mintcream            F5           FF            FA
mistyrose            FF           E4            E1
moccasin             FF           E4            B5
navajowhite          FF           DE            AD
navy                 00           00            80
oldlace              FD           F5            E6
olive                80           80            00
olivedrab            6B           8E            23
orange               FF           A5            00
orangered            FF           45            00
orchid               DA           70            D6
palegoldenrod        EE           E8            AA
palegreen            98           FB            98
paleturquoise        AF           EE            EE
palevioletred        DB           70            100
papayawhip           FF           EF            D5
peachpuff            FF           DA            B9
peru                 CD           85            3F
pink                 FF           C0            CB
plum                 DD           A0            DD
powderblue           B0           E0            E6
purple               80           00            80
red                  FF           00            00
rosybrown            BC           8F            8F
royalblue            41           69            E1
saddlebrown          8B           45            13
salmon               FA           80            72
sandybrown           F4           A4            60
seagreen             2E           8B            57
seashell             FF           F5            EE
sienna               A0           52            2D
silver               C0           C0            C0
skyblue              87           CE            EB
slateblue            6A           5A            CD
slategray            70           80            90
snow                 FF           FA            FA
springgreen          00           FF            7F
steelblue            46           82            B4
tan                  D2           B4            8C
teal                 00           80            80
thistle              D8           BF            D8
tomato               FF           63            47
turquoise            40           E0            D0
violet               EE           82            EE
wheat                F5           DE            B3
whitesmoke           F5           F5            F5
yellow               FF           FF            00
yellowgreen          9A           CD            32

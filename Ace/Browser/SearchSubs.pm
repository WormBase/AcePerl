package Ace::Browser::SearchSubs;

# Common constants and subroutines used by the various search scripts

use strict;
use vars qw(@ISA @EXPORT);
use Ace::Browser::AceSubs qw(Configuration Url ResolveUrl);
use CGI qw(:standard *table *Tr *td);

require Exporter;
@ISA = qw(Exporter);

######################### This is the list of exported subroutines #######################
@EXPORT = qw(
	     MAXOBJECTS 
	     SEARCH_ICON
	     AceSearchTable AceResultsTable AceSearchOffset AceSearchMenuBar
	     DisplayInstructions
	    );

# ----- constants used by the pattern search script ------
use constant ROWS           => 10;    # how many rows to allocate for search results
use constant COLS           =>  5;    #  "   "   columns   "       "    "      "
use constant MAXOBJECTS     => ROWS * COLS;  # total objects per screen
use constant SEARCH_ICON    => '/icons/search.gif';
use constant SPACER_ICON    => '/icons/spacer.gif';
use constant LEFT_ICON      => '/icons/cylarrw.gif';
use constant RIGHT_ICON     => '/icons/cyrarrw.gif';

# subroutines only used in the search scripts
sub DisplayInstructions {
  my ($title,@instructions) = @_;

  my $images = Configuration->Random_picts;
  my $script = Configuration->Pic_script;
  my $cross   = Configuration->Cross_icon;

  if ($images && $script) {
    $script = ResolveUrl("$script$images");
    print img({-src=>$script,-alt=>'[random picture]',-align=>'RIGHT'});
  }

  foreach (@instructions) { $_ = img({-src=>$cross,-alt=>'*'}). ' ' .$_; }
  print 
    h1($title),
    font({-size=>-1},
	 p(\@instructions)
	 ),
	 br({-clear=>'all'});
}


sub AceSearchOffset {
  my $offset = param('offset') || 0;
  $offset += param('scroll') if param('scroll');
  $offset;
}

sub AceSearchTable {
  my ($title,@body) = @_;
  print
    start_form(-action=>url(-absolute=>1,-path_info=>1).'#searchagain'),
    a({-name=>'search'},''),
    table({-border=>1,-cellspacing=>0,-cellpadding=>4,-width=>'100%',-align=>'CENTER'},
	  TR(th({-class=>'searchtitle'},$title),
	     
	     TR({-valign=>'CENTER'},
		td({-class=>'searchbody'},@body)))),
    end_form;
}

sub AceResultsTable {
  my ($objects,$count,$offset,$title) = @_;
  Delete('scroll');
  param(-name=>'offset',-value=>$offset);
  my @cheaders = map { $offset + ROWS * $_ } (0..(@$objects-1)/ROWS) if @$objects;
  my @rheaders = (1..min(ROWS,$count));

  $title ||= 'Search Results';

  print 
    p(a({-href=>'#search',-name=>'searchagain'},
	    'Search Again'), "|", a({-href=>(url(-absolute=>1,path_info=>1))},
				    'Clear Search')),
    a({-name=>'results'}),
    start_table({-border=>1,-cellspacing=>0,-cellpadding=>4,-width=>'100%',-align=>'CENTER',-class=>'resultsbody'}),
    TR(th({-class=>'resultstitle'},$title));
  unless (@$objects) {
    print end_table,p();
    return;
  }

  print start_Tr,start_td;

  my $need_navbar = $offset > 0 || $count >= MAXOBJECTS;
  my @buttons = make_navigation_bar($offset,$count) if $need_navbar;

  print table({-width=>'50%',-align=>'CENTER'},Tr(@buttons)) if $need_navbar;
  print table({-width=>'100%'},tableize(ROWS,COLS,\@rheaders,\@cheaders,@$objects));

  print end_td,end_Tr,end_table,p();
}

sub AceSearchMenuBar {
  my $quovadis = url(-absolute=>1,-path=>1);
  my @searches = Configuration->searches;
  return unless @searches;

  my @cells;
  my ($url,$home) = @{Configuration->Home};

  if (my $bookmark = cookie('HOME_'.Configuration->Name)) {
    $bookmark=~s/ /+/g;  # some bug
    push(@cells,a({-href=>$bookmark,-target=>'_top'},$home));
  } else {
    push(@cells,a({-href=>$url,-target=>'_top'},$home)) if $home;
  }

  foreach my $page (@searches) {
    push @cells,($quovadis =~ /$page/)
        ? strong(font({-color=>'red'},Configuration->searches($page)))
	: a({-href=>ResolveUrl($page),-target=>'_top'},
	    Configuration->searches($page));
  }
  return 
    table({-border=>0,-bgcolor=>"#eeeeff",-width=>'100%',-class=>'search',-cellpadding=>0, -cellspacing=>0, -height=>20},
	  TR({-class=>'search',-align=>'CENTER'},td({-class=>'search'},\@cells)));
}

# ------ ugly internal routines for scrolling along the search results list -----
sub make_navigation_bar {
  my($offset,$count) = @_;
  my (@buttons);
  my ($page,$pages) =  (1+int($offset/MAXOBJECTS),1+int($count/MAXOBJECTS));
  my $c = Configuration();
  my $left = $c->Arrowl_icon || LEFT_ICON;
  my $right = $c->Arrowr_icon || RIGHT_ICON;

  push(@buttons,td({-align=>'RIGHT',-valign=>'MIDDLE'},
		   $offset > 0 
		               ? a({-href=>self_url() . '&scroll=-' . MAXOBJECTS},
				      img({-src=>$left,-alt=>'< PREVIOUS',-border=>0}))
                               : img({-src=>SPACER_ICON,-alt=>''})
		   )
      );

  my $p = 1;
  while ($pages/$p > 25) { $p++; }
  my (@v,%v);
  for (my $i=1;$i<=$pages;$i++) {
    next unless ($i == $page) or (($i-1) % $p == 0);
    my $s = ($i - $page) * MAXOBJECTS;
    push(@v,$s);
    $v{$s}=$i;
  }
  my @hidden;
  Delete('scroll');
  Delete('Go');
  foreach (param()) {
    push(@hidden,hidden(-name=>$_,-value=>[param($_)]));
  }

  push(@buttons,
       td({-valign=>'MIDDLE',-align=>'CENTER'},
	  start_form({-name=>'form1'}),
	  submit(-name=>'Go',-label=>'Go to'),
	  'page',
	  popup_menu(-name=>'scroll',-Values=>\@v,-labels=>\%v,
		     -default=>($page-1)*MAXOBJECTS-$offset,
		     -override=>1,
		     -onChange=>'document.form1.submit()'),
	  "of $pages",
	  @hidden,
	  end_form()
	 )
      );

  push(@buttons,td({-align=>'LEFT',-valign=>'MIDDLE'},
		   $offset + MAXOBJECTS <= $count 
		   ? a({-href=>self_url() . '&scroll=+' . MAXOBJECTS},
		       img({-src=>$right,-alt=>'NEXT >',-border=>0}))
		   : img({-src=>SPACER_ICON,-alt=>''})
		  )
      );
  @buttons;
}

sub min { return $_[0] < $_[1] ? $_[0] : $_[1] }
#line 295

sub tableize {
    my($rows,$columns,$rheaders,$cheaders,@elements) = @_;
    my($result);
    my($row,$column);
    $result .= TR($rheaders ? th('&nbsp;') : (),th({-align=>'LEFT'},$cheaders)) 
      if $cheaders and @$cheaders > 1;
    for ($row=0;$row<$rows;$row++) {
	next unless defined($elements[$row]);
	$result .= "<TR>";
        $result .= qq(<TH  ALIGN=LEFT CLASS="search">$rheaders->[$row]</TH>) if $rheaders;
	for ($column=0;$column<$columns;$column++) {
	    $result .= qq(<TD VALIGN=TOP CLASS="search">) . $elements[$column*$rows + $row] . "</TD>"
		if defined($elements[$column*$rows + $row]);
	}
	$result .= "</TR>";
    }
    return $result;
}

1;

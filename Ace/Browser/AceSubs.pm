package Ace::Browser::AceSubs;

use strict;
use Ace::Browser::SiteDefs;
use Ace 1.51;
use CGI qw(:standard escape);

use vars qw/@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS %DB %OPEN $HEADER/;

require Exporter;
@ISA = qw(Exporter);

######################### This is the list of exported subroutines #######################
@EXPORT = qw(
	     GetAceObject AceInit AceHeader AceError AceMissing AceRedirect 
	     AceMultipleChoices OpenDatabase TypeSelector Style Url Object2URL
	     ObjectLink Header Footer Configuration DB_Name);
@EXPORT_OK = qw(DoRedirect Toggle ResolveUrl);
%EXPORT_TAGS = ( );

use constant DEFAULT_DATABASE  => 'default';
use constant PRIVACY           => 'misc/privacy';  # privacy/cookie statement
use constant SEARCH_BROWSE     => 'search';   # a fallback search script
my %VALID;  # cache for get_symbolic() lookups

*DB_Name = \&get_symbolic;

# get the configuration object for this database
sub Configuration {
  return unless my $s = get_symbolic();
  return Ace::Browser::SiteDefs->getConfig($s) || Ace::Browser::SiteDefs->getConfig('default');
}

# Contents of the HTML footer.  It gets printed immediately before the </BODY> tag.
# The one given here generates a link to the "feedback" page, as well as to the
# privacy statement.  You may or may not want these features.
sub Footer {
  if (my $footer = Configuration->Footer) {
    return $footer;
  }
  my $webmaster = $ENV{SERVER_ADMIN} || 'webmaster@sanger.ac.uk';

  my $obj_name =  escape(param('name'));
  my $obj_class = escape(param('class')) || ucfirst url(-relative=>1);
  my $referer   = escape(self_url());
  my $name = Configuration->Name;

  # set up the feedback link
  my $feedback_link = Configuration->Feedback_recipients && 
      $obj_name && 
	  (url(-relative=>1) ne 'feedback') ?
    a({-href=>ResolveUrl("misc/feedback/$name","name=$obj_name&class=$obj_class&referer=$referer")},
      "Click here to send data or comments to the maintainers")
      : '';

  # set up the privacy statement link
  my $privacy_link = url(-relative=>1) ne PRIVACY() ? 
    a({ -href=>ResolveUrl(PRIVACY."/$name") },'Privacy Statement')
      : '';

  # Either generate a pointer to ACeDB home page, or the copyright statement.
  my $clink = Configuration->Copyright ? a({-href=>Configuration->Copyright,-target=>"_new"},'Copyright Statement')
                                       : qq(<A HREF="http://www.sanger.ac.uk/Software/Acedb">ACeDB Home Page</A>);


  return <<END;
<TABLE WIDTH="660" BORDER=0 CELLPADDING=0 CELLSPACING=0>
<TR CLASS="technicalinfo">
    <TD  CLASS="small" VALIGN="TOP">
    <A HREF="http://stein.cshl.org/AcePerl/">AcePerl Home Page</A><br>
    $clink
    </TD>
    <TD  CLASS="small" ALIGN=RIGHT VALIGN=TOP><p><strong>$feedback_link</strong><br>
    $privacy_link<br>
    <A HREF="mailto:$webmaster"><address>$webmaster</address></A><br>
    </TD>
</TR>
</TABLE>
END
}

sub Header {
  return Configuration()->Banner;
}

# A consistent stylesheet across pages
sub Style {
    my $stylesheet = Configuration->Stylesheet;
    return { -src => $stylesheet };
}

# Subroutines used by all scripts.
# Will generate an HTTP 'document not found' error if you try to get an 
# undefined database name.  Check the return code from this function and
# return immediately if not true (actually, not needed because we exit).
sub AceInit   {
  $HEADER = 0;

  %OPEN = map {$_ => 1} split(' ',param('open')) if param('open');
  return 1 if Configuration();

  # if we get here, it is a big NOT FOUND error
  print header(-status=>'404 Not Found',-type=>'text/html');
  $HEADER++;
  print start_html(-title => 'Database Not Found',
		   -style => Ace::Browser::SiteDefs->getConfig(DEFAULT_DATABASE)->Style,
		  ),
        h1('Database not found'),
        p('The requested database',i(get_symbolic()),'is not recognized',
	  'by this server.');
  print p('Please return to the',a({-href=>referer()},'referring page.')) if referer();
  print end_html;
  Apache::exit(0) if defined &Apache::exit;  # bug out of here!
  exit(0);
}

################## canned header ############
sub AceHeader {

  my %searches = map {$_=>1} Configuration->searches;
  my $quovadis = url(-relative=>1);

  my @cookies;
  my $db = Configuration->Name || get_symbolic();


  my $referer  = referer();
  $referer =~ s!^http://[^/]+!! if defined $referer;
  my $home = Configuration->Home->[0] if Configuration->Home;

  if ($referer && $home && index($referer,$home) >= 0) {
    my $bookmark = cookie(
			  -name=>"HOME_${db}",
			  -value=>$referer,
			  -path=>'/');
    push(@cookies,$bookmark);
  }

  if ($searches{$quovadis}) {
    Delete('Go');
    my $search_name = "SEARCH_${db}_${quovadis}";
    my $search_data = cookie(-name  => $search_name,
			     -value => query_string(),
			     -path=>'/',
			    );
    my $last_search = cookie(-name=>"ACEDB_$db",
			     -value=>$quovadis,
			     -path=>'/');
    push(@cookies,$search_data,$last_search);
  }


  print header(-cookie=>\@cookies,@_) if @cookies;
  print header(@_)               unless @cookies;

  $HEADER++;
}


sub Open_table{
print '<table width=660>
<tr>
<td>';
}

sub Close_table{
print '</tr>
</td>
</table>';
}


###############  redirect to a different report #####################
sub AceRedirect {
  my ($report,$object) = @_;

  my $url = Configuration->display($report,'url');
  my $destination = ResolveUrl($url => "name=$object");
  AceHeader(-Refresh => "1; URL=$destination");
  print start_html (
			 '-Title' => 'Redirect',
			 '-Style' => Style(),
			),
    h1('Redirect'),
    p("The object you requested,",b($object),"is not directly available.",
	   "However a",a({-href=>$destination},$report),"object of the same name is."),
    p("This page will automatically display the requested object in",
	   "two seconds.",a({-href=>$destination},'Click on this link'),'to load the page immediately.'),
    end_html();
}

sub AceMultipleChoices {
  my ($symbol,$report,$objects) = @_;
  if (@$objects == 1) {
    my $url = Configuration->display($report,'url');
    my $destination = ResolveUrl($url => "name=$objects->[0]");
    AceHeader(-Refresh => "1; URL=$destination");
    print start_html (
			   '-Title' => 'Redirect',
			   '-Style' => Style(),
			),
      h1('Redirect'),
      p("Automatically transforming this query into a request for corresponding object",
	     a({-href => Object2URL($objects->[0])},$objects->[0]->class.':',$objects->[0])),
      p("Please wait..."),
      FOOTER(),
      end_html();
    return;
  }
  AceHeader();
  print start_html (
		    '-Title' => 'Multiple Choices',
		    '-Style' => Style(),
		   ),
    h1('Multiple Choices'),
    p("Multiple $report objects correspond to $symbol.",
      "Please choose one:"),
    ol(
       li([
	   map {a({-href => Object2URL($_)},$_->class.':',$_)} @$objects
	  ])
	    ),
	 Footer(),
	 end_html();
}

################ open a database #################
sub OpenDatabase {
  my $name = shift || get_symbolic();
  AceInit();
  $name =~ s!/$!!;
  my $db = $DB{$name};
  unless ($db and $db->ping) {
    my ($host,$port) = getDatabasePorts($name);
    return $DB{$name} = Ace->connect(-host=>$host,-port=>$port,-timeout=>50);
  }
  return $db;
}

# return host and port for symbolic database name
sub getDatabasePorts {
  my $name = shift;
  my $config = Ace::Browser::SiteDefs->getConfig($name);
  return ($config->Host,$config->Port) if $config;

  # If we get here, then try getservbynam()
  # I think this is a bit of legacy code.
  my @s = getservbyname($name,'tcp');
  return unless @s;
  return unless $s[2]>1024;  # don't allow connections to reserved ports
  return ('localhost',$s[2]);
}

sub ResolveUrl {
    my ($url,$param) = @_;
    my ($main,$query,$frag) = $url =~ /^([^?\#]+)\??([^\#]*)\#?(.*)$/;

    # search is relative to the Ace::Browser::SiteDefs.pm file
    $main = Ace::Browser::SiteDefs->resolvePath($main) unless $main =~ m!^/!;
#    my $name = Configuration->Name;
#    $main .= "/$name" unless index($main,$name) >= 0;
    $main .= CGI::path_info() if CGI::path_info();

    $main .= "?$query" if $query; # put the query string back
    $main .= "?$param" if $param and !$query;
    $main .= "&$param" if $param and  $query;
    $main .= "#$frag" if $frag;
    return $main;
}

# general mapping from a display to a url
sub Object2URL {
    my ($object,$extra) = @_;
    my ($name,$class);
    if (ref($object)) {
	($name,$class) = ($object->name,$object->class);
    } else {
	($name,$class) = ($object,$extra);
    }
    my $display = url(-relative=>1);
    my ($disp,$parameters) = Configuration->map_url($display,$name,$class);
    return Url($disp,$parameters);
}

sub Url {
  my ($display,$parameters) = @_;
  my $url = Configuration->display($display,'url');
  return ResolveUrl($url,$parameters);
}


sub ObjectLink {
  my $object     = shift;
  my $link_text  = shift;
  return a({-href=>Object2URL($object,@_),-name=>"$object"},$link_text || "$object");
}

sub AceError {
    my $msg = shift;
    print header() unless $HEADER++;
    print start_html('-title'=>'Parameter Error',
			  '-style'=>Style()
			  ),
			    h1('Error'),CGI::font({-color=>'red'},$msg),
							     CGI::hr(),Footer;
    if (defined &Apache::exit) {
	Apache->exit(0);
    } else {
	exit 0;
    }
}

sub AceMissing {
    my ($class,$name) = @_;
    $class ||= param('class');
    $name  ||= param('name');
    print header() unless $HEADER++;
    print
      start_html(-title=>"$name",
		 -style=>Style()),
      Header,
      h1("$class: $name"),
      strong('No further information about this object in the database'),
      Apache->exit(0) if defined &Apache::exit;
    exit(0);
}

sub get_symbolic {

  if (exists $ENV{MOD_PERL}) {  # the easy way
    if (my $r = Apache->request) {
      if (my $conf = $r->dir_config('AceBrowserConf')) {
	my ($name) = $conf =~ m!([^/]+)\.pm$!;
	return $name if $name;
      }
    }
  }

  # otherwise, the hard way
  (my $name = path_info())=~s!^/!!;
  return $name if defined $name && $name ne '';  # get from additional path info
  my $path = url(-absolute=>1);
  return $VALID{$path} if exists $VALID{$path};
  my @path = split '/',$path;
  pop @path;
  for my $name (reverse @path) {
    return $VALID{$path} if exists $VALID{$name};
    return $VALID{$path} = $name if Ace::Browser::SiteDefs->getConfig($name);
    $VALID{$path} = undef;
  }
  return;
}

# Choose a set of displayers based on the type.
sub TypeSelector {
    my ($name,$class) = @_;
    $name = "$name" if ref($name);  # fix obscure bug in escape
    my ($n,$c) = (escape($name),escape($class));
    my @rows;

    my $HOME_ICON   = Configuration->Home_icon;
    my $SEARCH_ICON = Configuration->Search_icon;

    # use cookie information to select the URL for
    # the search icon
    my $db = get_symbolic();
    my $search_bookmark = '';
    if (my $last_search_script   = cookie("ACEDB_$db")) {
      my $query_string = cookie("SEARCH_${db}_${last_search_script}");
      $search_bookmark = "$last_search_script";
      $search_bookmark .= "?$query_string" if $query_string;
    }
    $search_bookmark=~s/ /+/g;
    $search_bookmark  ||= Configuration->Searches->[0] if Configuration->Searches;
    $search_bookmark  ||= SEARCH_BROWSE;

    # if there's a home page, then add it to the bar
    my $bookmark = cookie('HOME_'.get_symbolic());
    $bookmark=~s/ /+/g;  # some bug
    my $home = Configuration->Home->[0] if Configuration->Home;

    if ($home) {
      my $url   = $bookmark || $home;
      my $label = Configuration->Home->[1];
      push(@rows,
	   td({-align=>'CENTER',-class=>'small'},
	      a({-href=>$url,-target=>'_top'},
		img({-src=>$HOME_ICON,-alt=>'[image]',-border=>0}).
		br().$label)
	     ))
	if $HOME_ICON;
    }

    # everybody gets the standard search:
    push (@rows,
	td({-align=>'CENTER',-class=>'small'},
		a({-href=>ResolveUrl($search_bookmark),-target=>'_top'},
		  img({-src=>$SEARCH_ICON,-alt=>'[image]',-border=>0}) . br().
		  "Search")
		))
      if $SEARCH_ICON;

    # add the special displays
    my @displays       = Configuration->class2displays($class);
    my @basic_displays = Configuration->class2displays('default');
    @basic_displays    = Ace::Browser::SiteDefs->getConfig(DEFAULT_DATABASE)->class2displays('default') 
      unless @basic_displays;

    my $display = url(-absolute=>1,-path=>1);

    foreach (@displays,@basic_displays) {
 	my ($url,$icon,$label) = @{$_}{qw/url icon label/};
	next unless $url;
	my $u = ResolveUrl($url,"name=$n&class=$c");
	$url =~ s/\#.*$//;

	my $active = $url =~ /^$display/;
	my $cell;
	unless ($active) {
	  $cell = defined $icon ? a({-href=>$u,-target=>'_top'},
				    img({-src=>$icon,-border=>0}).br().$label)
				: a({-href=>$u,-target=>'_top'},$label);
	} else {
	  $cell = defined $icon ? img({-src=>$icon,-border=>0}).br().font({-color=>'red'},$label)
				: font({-color=>'red'},$label);
	}
	  push (@rows,td({-align=>'CENTER',-class=>'small'},$cell));
	}
    return table(TR({-valign=>'bottom'},@rows));
}


# redirect to the URL responsible for an object
sub DoRedirect {
    my $obj = shift;
    print redirect(Object2URL($obj));
}

# Toggle a subsection open and close
sub Toggle {
    my ($section,$label,$count,$noplural,$nocount) = @_;
    my %open = %OPEN;

    $label ||= $section;
    my $img;
    if (exists $open{$section}) {
	delete $open{$section};
	$img =  img({-src=>'/icons/triangle_down.gif',-alt=>'^',
			-height=>6,-width=>11,-border=>0}),
    } else {
	$open{$section}++;
	$img =  img({-src=>'/icons/triangle_right.gif',-alt=>'&gt;',
			-height=>11,-width=>6,-border=>0}),
	my $plural = ($noplural or $label =~ /s$/) ? $label : "${label}s";
	$label = font({-color=>'red'},$nocount ? $plural : "$count $plural");
    }
    param(-name=>'open',-value=>join(' ',keys %open));
    my $url = url(-absolute=>1,-path_info=>1,-query=>1);

    my $href = a({-href=>"$url#$section",-name=>$section},$img.$label);
    if (wantarray ){
      return ($href,$OPEN{$section})
    } else {
      print $href,br;
      return $OPEN{$section};
    }
}

# open database, return object requested by CGI parameters
sub GetAceObject {
  my $db = OpenDatabase() ||  AceError("Couldn't open database."); # exits
  my $name = param('name') or return;
  my $class = param('class') or return;
  my @objs = $db->fetch($class => $name);
  if (@objs > 1) {
    AceMultipleChoices($name,'',\@objs);
    return;
  }
  return $objs[0];
}

1;

=head1 NAME

Ace::Browser::AceSubs - Subroutines for AceBrowser

=head1 SYNOPSIS

  use Ace;
  use Ace::Browser::AceSubs;
  use CGI qw(:standard);

  my $obj = GetAceObject() || AceMissing();
  AceHeader();

  print start_html('AceBrowser Report');
  print Header();
  print TypeSelector($obj);
  print h1("Report for $obj");
  print Footer();

  See L<Ace::Graphics::Panel> and L<Ace::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws a series of filled rectangles connected by up-angled
connectors or "hats".  The rectangles indicate exons; the hats are
introns.  The direction of transcription is indicated by a small arrow
at the end of the glyph, rightward for the + strand.

The feature must respond to the exons() and optionally introns()
methods, or it will default to the generic display.  Implied introns
(not returned by the introns() method) are drawn in a contrasting
color to explicit introns.

=head2 OPTIONS

In addition to the common options, the following glyph-specific
option is recognized:

  Option                Description                    Default
  ------                -----------                    -------

  -implied_intron_color The color to use for gaps      gray
                        not returned by the introns()
                        method.

  -draw_arrow           Whether to draw arrowhead      true
                        indicating direction of
                        transcription.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Ace::Sequence>, L<Ace::Sequence::Feature>, L<Ace::Graphics::Panel>,
L<Ace::Graphics::Track>, L<Ace::Graphics::Glyph::anchored_arrow>,
L<Ace::Graphics::Glyph::arrow>,
L<Ace::Graphics::Glyph::box>,
L<Ace::Graphics::Glyph::primers>,
L<Ace::Graphics::Glyph::segments>,
L<Ace::Graphics::Glyph::toomany>,
L<Ace::Graphics::Glyph::transcript>,

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

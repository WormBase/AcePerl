# ========= $NAME =========
# symbolic name of the database (defaults to name of file, lowercase)
$NAME = 'default';

# ========= $HOST  =========
# name of the host to connect to
$HOST = 'formaggio.cshl.org';

# ========= $PORT  =========
# Port number to connect to
$PORT = 400001;

# ========= $STYLESHEET =========
# stylesheet to use
$STYLESHEET = 'http://stein.cshl.org/stylesheets/aceperl.css';

# ========= $PICTURES ==========
# Where to write temporary picture files to:
#   The URL and the physical location, which must be writable
# by the web server.
# You probably will have to change this.
@PICTURES = ('/ace_images' => '/var/tmp/ace_images');

# ========= @SEARCHES  =========
# search scripts available
# NOTE: the order is important
@SEARCHES   = (
	       'searches/text'    => 'Text Search',
	       'searches/browser'  => 'Class Browser',
	       'searches/query'   => 'Acedb Query',
	       );
$SEARCH_ICON = '/icons/unknown.gif';

# ========= %HOME  =========
# Home page URL
@HOME      = (
	      'http://stein.cshl.org/AcePerl' => "AcePerl Home Page"
	     );

# ========= %DISPLAYS =========
# displays to show
%DISPLAYS = (	
	     tree => { 
		      'url'     => "generic/tree",
		      'label'   => 'Tree Display',
		      'icon'    => '/icons/text.gif' },
	     pic => { 
		     'url'     => "generic/pic",
		     'label'   => 'Graphic Display',
		     'icon'    => '/icons/image2.gif' },
	    );

# ========= %CLASSES =========
# displays to show
%CLASSES = (	
	    # default is a special "dummy" class to fall back on
	     Default => [ qw/tree pic/ ],
	   );



# ========= &URL_MAPPER  =========
# mapping from object type to URL.  Return empty list to fall through
# to default.
sub URL_MAPPER {
  my ($display,$name,$class) = @_;

  # Small Ace inconsistency: Models named "#name" should be
  # transduced to Models named "?name"
  $name = "?$1" if $class eq 'Model' && $name=~/^\#(.*)/;

  my $n = CGI::escape("$name"); # looks superfluous, but avoids Ace::Object name conversions errors
  my $c = CGI::escape($class);

  # pictures remain pictures
  if ($display eq 'pic') {
    return ('pic' => "name=$n&class=$c");
  }
  # otherwise display it with a tree
  else {
    return ('tree' => "name=$n&class=$c");
  }
}

# ========= $BANNER =========
# Banner HTML
# This will appear at the top of each page. 
$BANNER = <<END;
<center><span class=banner><font size=+3>Default Database</font></span></center><p>
END

# ========= $FOOTER =========
# Footer HTML
# This will appear at the bottom of each page
$FOOTER = '';

1;

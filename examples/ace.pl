#!/usr/local/bin/perl

# Simple interface to acedb.
# Uses readline for command-line editing if available.

use Ace;
use Getopt::Long;
use Text::ParseWords;
use strict vars;
use vars qw/@CLASSES @HELP_TOPICS/;
use constant DEBUG => 0;

my ($HOST,$PORT,$PATH,$TCSH);
GetOptions('host=s' => \$HOST,
	   'port=i' => \$PORT,
	   'path=s' => \$PATH,
	   'tcsh'   => \$TCSH,
	  ) || die <<USAGE;
Usage: $0 [options]
Interactive Perl client for ACEDB

Options (can be abbreviated):
       -host <hostname>  Server host (localhost)
       -port <port>      Server port (200005)
       -path <db path>   Local database path (no default)
       -tcsh             Use T-shell completion mode (no)

Respects the environment variables \$ACEDB_HOST and \$ACEDB_PORT, if present.
You can edit the command line using the cursor keys and emacs style
key bindings.  Use up and down arrows (or ^P, ^N) to access the history.
The tab key completes partial commands.  In tcsh mode, the tab key cycles 
among the completions, otherwise pressing the tab key a second time lists 
all the possibilities.
USAGE
;

$HOST ||= $ENV{ACEDB_HOST} || 'localhost';
$PORT ||= $ENV{ACEDB_PORT} || 200005;
my $PROMPT = "aceperl> ";

my $DB = $PATH ? Ace->connect(-path=>$PATH) : Ace->connect(-host=>$HOST,-port=>$PORT);
$DB ||  die "Connection failure.\n";

if (@ARGV || !-t STDIN) {
  while (<>) {
    chomp;
    evaluate($_);
  }

} elsif (eval "require Term::ReadLine") {
  my $term = setup_readline();
  while (defined($_ = $term->readline($PROMPT)) ) {
    evaluate($_);
    $term->addhistory($_) if /\S/;
  }

} else {
  $| = 1;
  print $PROMPT;
  while (<>) {
    chomp;
    evaluate($_);
  } continue {
    print $PROMPT;
  }
}

sub evaluate {
  my $query = shift;
  if ($query=~/^(quit|exit)/i) {
    print "// A bientot!\n";
    exit 0;
  }
  $DB->db->query($_) || return undef;
  $DB->db->status == STATUS_ERROR && return undef;
  while ($DB->db->status == STATUS_PENDING) {
    my $h = $DB->db->read;
    $h=~tr/\0//d; # get rid of nulls in data stream!
    print $h;
  }
}

sub setup_readline {
  my $term = new Term::ReadLine 'aceperl';
  my (@commands) = qw/quit help classes model find follow grep longgrep list 
           show is remove query where table-maker biblio dna peptide keyset-read
           spush spop swap sand sor sxor sminus parse pparse write edit 
	   eedit shutdown who data_version kill status date time_stamps
	   count clear save undo wspec/;
  readline::rl_basic_commands(@commands);
  readline::rl_set('TcshCompleteMode', 'On') if $TCSH;
  $readline::rl_special_prefixes='"';
  $readline::rl_completion_function=\&complete;
  $term;
}

# This is a big function for command completion/guessing.
sub complete {
  my($txt,$line,$start) = @_;
  return ('"') if $txt eq '"';  # to fix wierdness

  # Examine current word in the context of the two previous ones
  $line = substr($line,0,$start+length($txt)); # truncate
  $line .= '"' if $line=~tr/"/"/ % 2;  # correct odd quote parity errors
  my(@tokens) = quotewords(' ',0,$line);
  push(@tokens,$txt) unless $txt || $line=~/\"$/;
  my $old = $txt;
  $txt = $tokens[$#tokens]; 

  if (DEBUG) {
    warn "\n",join(':',@tokens)," (text = $txt, start = $start, old=$old)\n";
    $readline::force_redraw++;
    readline::redisplay();
  }

  if (lc($tokens[$#tokens-2]) eq 'find') {
    my $count = $DB->count($tokens[$#tokens-1],"$txt*");
    if ($count > 250) {
      warn "\r\n($count possibilities -- too many to display)\n";
      $readline::force_redraw++;
      readline::redisplay();
      return;
    } else {
      my @obj = $DB->list($tokens[$#tokens-1],"\"$txt*\"");
      if ($txt=~/(.+\s+)\S*$/) {
	my $common_prefix = $1;
	return map { "$_\"" } 
	       map { substr($_,index($_,$common_prefix)+length($common_prefix))  }
	       grep(/^$txt/i,@obj);
      } else {
	return map { $_=~/\s/ ? "\"$_\"" : $_ } grep(/^$txt/i,@obj);
      }
    }
  }

  if (lc($tokens[$#tokens-1]) =~/^(find|model)/) {
    @CLASSES = $DB->classes() unless @CLASSES;
    return grep(/^$txt/i,@CLASSES);
  }

  if ($tokens[$#tokens-1] =~ /^list|show/i) {
    if ($line=~/-f\s+\S*$/) {
      return readline::rl_filename_list($txt);
    } 
    return grep (/^$txt/i,qw/-h -a -p -j -T -b -c -f/);
  }

  if ($tokens[$#tokens-1] =~ /^help/i) {
    @HELP_TOPICS = get_help_topics() unless @HELP_TOPICS;
    return grep(/^$txt/i,'query_syntax',@HELP_TOPICS);
  }
  
  if (DEBUG) {
    warn "\n",join(':',@_),"\n";
    $readline::force_redraw++;
    readline::redisplay();
  }

  return grep(/^$txt/i,@readline::rl_basic_commands);
}

sub get_help_topics {
  return () unless $DB;
  my $result = $DB->raw_query('help topics');
  return grep(/^About/../^nohelp/,split(' ',$result));
}

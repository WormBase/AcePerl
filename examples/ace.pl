#!/usr/local/bin/perl

# Simple interface to acedb.
# Uses readline for command-line editing if available.
use lib './blib/arch','./blib/lib';
use Ace 1.43;
use Getopt::Long;
use Text::ParseWords;
use strict vars;
use vars qw/@CLASSES @HELP_TOPICS/;
use constant DEBUG => 0;

my ($HOST,$PORT,$PATH,$TCSH,@EXEC);
GetOptions('host=s' => \$HOST,
	   'port=i' => \$PORT,
	   'path=s' => \$PATH,
	   'tcsh'   => \$TCSH,
	   'exec=s' => \@EXEC,
	  ) || die <<USAGE;
Usage: $0 [options]
Interactive Perl client for ACEDB

Options (can be abbreviated):
       -host <hostname>  Server host (localhost)
       -port <port>      Server port (200005)
       -path <db path>   Local database path (no default)
       -tcsh             Use T-shell completion mode (no)
       -exec <command>   Run a command and quit

Respects the environment variables \$ACEDB_HOST and \$ACEDB_PORT, if present.
You can edit the command line using the cursor keys and emacs style
key bindings.  Use up and down arrows (or ^P, ^N) to access the history.
The tab key completes partial commands.  In tcsh mode, the tab key cycles 
among the completions, otherwise pressing the tab key a second time lists 
all the possibilities.

You may use multiple -exec switches to run a sequence of commands, or
separate multiple commands in a single string by semicolons:

    ace.pl -e 'find Author Thierry-Mieg*' -e 'show'
    ace.pl -e 'find Author Thierry-Mieg*; show'
USAGE
;

$HOST ||= $ENV{ACEDB_HOST} || 'localhost';
$PORT ||= $ENV{ACEDB_PORT} || 200005;
my $PROMPT = "aceperl> ";

my $DB = $PATH ? Ace->connect(-path=>$PATH) : Ace->connect(-host=>$HOST,-port=>$PORT);
$DB ||  die "Connection failure.\n";

if (@EXEC) {
  foreach (@EXEC) { 
    foreach (split (';'))
      { evaluate($_); }
  }
  exit 0;
}

if (@ARGV || !-t STDIN) {
  while (<>) {
    chomp;
    evaluate($_);
  }

} elsif (eval "require Term::ReadLine") {
  my $term = setup_readline();
  while (defined($_ = $term->readline($PROMPT)) ) {
    evaluate($_);
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
quit();

sub quit {
  print "\n// A bientot!\n";
  $DB->db->query('quit');
  exit 0;
}

sub evaluate {
  my $query = shift;
  my @commands;
  if ($query=~/^(quit|exit)/i) {
    quit();
    exit 0;
  }
  if ($query =~ /^(p?parse) (?!=)(.*)/i) {
    push (@commands,setup_parse($1,$2));
  } else {
    push (@commands,$query);
  }

  foreach (@commands) {
    print "$_\n" if @commands > 1;

    $_ = setup_remote_parse($_) if /^parse (?!=)/ && !$PATH;

    $DB->db->query($_) || return undef;
    if ($DB->db->status == STATUS_ERROR) {
      print "[Ace error] status code ",$DB->db->status,"\n";
      return undef; 
    }

    while ($DB->db->status == STATUS_PENDING) {
      my $h = $DB->db->read;
      $h=~tr/\0//d; # get rid of nulls in data stream!
      print $h;
    }

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

  debug ("\n",join(':',@tokens)," (text = $txt, start = $start, old=$old)");
  
  if (lc($tokens[$#tokens-2]) eq 'find') {
    my $count = $DB->count($tokens[$#tokens-1],"$txt*");
    if ($count > 250) {
      warn "\r\n($count possibilities -- too many to display)\n";
      $readline::force_redraw++;
      readline::redisplay();
      return;
    } else {
      my @obj = $DB->list($tokens[$#tokens-1],"$txt*");
      debug("list(",$tokens[$#tokens-1],',',"$txt*",") :",scalar(@obj)," objects retrieved");
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

  debug(join(':',@_));

  return grep(/^$txt/i,@readline::rl_basic_commands);
}

# This handles the
sub setup_parse {
  my ($command,$file) = @_;
  my (@files) = glob($file);

  # if we're local, then we just create a series 
  # of parse commands and let tace take care of reading
  # the file
  return map {"parse $_"} @files if $PATH;

  # if we're talking to a remote server, we create a series of parse 
  # commands and stop at the first file that we find
  my @c;
  local(*F);
  local($/) = undef;  # file slurp
  foreach (@files) {
    open (F,$_) || die "Couldn't open $_: $!";
    print "parse $_\n";
    my $result = $DB->raw_query(scalar(<F>),1);
    print $result;
    return if $result=~/error|sorry/i and $command ne 'pparse';
    close F;
  }
  return ();
}

sub get_help_topics {
  return () unless $DB;
  my $result = $DB->raw_query('help topics');
  return grep(/^About/../^nohelp/,split(' ',$result));
}

sub debug {
  return unless DEBUG;
  my @text = @_;
  warn "\n",@text,"\n";
  $readline::force_redraw++;
  readline::redisplay();
}

#!/usr/local/bin/perl

# Simple interface to acedb.
# Uses readline for command-line editing if available.

use Ace;
use Getopt::Long;
use Text::ParseWords;
use strict vars;
use vars qw/@CLASSES/;

my ($HOST,$PORT);
GetOptions('host=s' => \$HOST,
	   'port=i' => \$PORT) || die <<USAGE;
Usage: $0 [options]
Interactive Perl client for ACEDB

Options:
       -host <hostname>  Server host (localhost)
       -port <port>      Server port (200005)
USAGE
;

$HOST ||= 'localhost';
$PORT ||= 200005;
my $PROMPT = "aceperl> ";

my $DB = Ace->connect(-host=>$HOST,-port=>$PORT) ||  die "Connection failure.\n";

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
  my (@upcase_commands) = @commands;
  grep(substr($_,0,1)=~tr/a-z/A-Z/,@upcase_commands);
  readline::rl_basic_commands(@commands,@upcase_commands);
  $readline::rl_completion_function=\&complete;
  $term;
}

sub complete {
  my($txt,$line,$start) = @_;
  my(@tokens) = quotewords('\s+',0,$line);

  if (lc($tokens[0]) eq 'find') {
    if ($tokens[2]) {
      my $count = $DB->count($tokens[1],"$tokens[2]*");
      if ($count > 250) {
	warn "\r\n($count possibilities -- too many to display)\n";
	$readline::force_redraw++;
	readline::redisplay();
      } else {
	my @obj = $DB->list($tokens[1],"$tokens[2]*");
	return grep(/^$txt/i,@obj);
      }
    } else {
      @CLASSES = $DB->classes() unless @CLASSES;
      return grep(/^$txt/,@CLASSES);
    }
  }

  if ($tokens[0] =~ /^list|show/i) {
    if ($line=~/-f\s+\S*$/) {
      return readline::rl_filename_list($txt);
    } 
    return grep (/^$txt/,qw/-h -a -p -j -T -b -c -f/);
  }
  return readline::use_basic_commands(@_);
}

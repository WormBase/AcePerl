use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
readline_setup();
my ($lib,$include) = find_ace();
my @OTHER_FLAGS;

exit -1 unless
  $location = _prompt('Location of libfree.a and libacecl.a',$lib);
exit -1 unless
  $headers = _prompt('Location of aceclient.h',$include);

WriteMakefile(
    'DISTNAME'     => 'AcePerl',
    'NAME'	   => 'Ace',
    'VERSION_FROM' => 'Ace.pm', # finds $VERSION
    'LIBS'	   => ["-L$location -lacecl -lfree -lc"],
    'DEFINE'	   => '',
    'OBJECT'    => '$(O_FILES)',
    'XSPROTOARG'   => '-noprototypes',
    'INC'	   => "-I$headers",
    'dist'      => {'COMPRESS'=>'gzip -9f', 'SUFFIX' => 'gz',
	            'ZIP'=>'/usr/bin/zip','ZIPFLAGS'=>'-rl'},
);

# search around for ace and return the location of the lib and include files
sub find_ace {
  my @roots = qw(. .. ../.. ../../.. /usr/local);
  unshift(@roots,$ENV{ACEDB_SRC}) if exists $ENV{ACEDB_SRC};
  unshift(@roots,(getpwnam('acedb'))[7]);
  unshift(@roots,(getpwnam('ace'))[7]);
  unshift(@roots,$ENV{HOME}) if exists $ENV{HOME};
  my @subs = qw(ace acedb ACE ACEDB);
  # look for a wh directory
  my ($src,$root,$sub);
 SEARCH:
  foreach $root (@roots) {
      next unless $root;
      foreach $sub (@subs) {
	  $src = "$root",last SEARCH if -d "$root/wh";
	  $src = "$root/$sub",last SEARCH if -d "$root/$sub/wh";
      }
  }
  if ($src) {
      my $olddir;
      chomp($olddir = `pwd`);
      chdir $src;
      chomp($src = `pwd`);
      chdir $olddir;
      warn "Found ACEDB source tree in $src.\n";
  } else {
      warn "Couldn't find ACEDB source tree.\n";
      return ('/usr/local/lib','/usr/local/include');
  }
  # If we get here, then we have a source tree to rummage through.
  # Now we need to find the appropriate bin directory for the
  # libraries.
  my $include = "$src/wh";
  my ($lib);
  my (@bins) = <$src/bin.*>;
  unshift (@bins,"$src/bin.$ENV{ACEDB_MACHINE}") if exists $ENV{ACEDB_MACHINE};
  foreach (@bins) {
    return ($_,$include) if -e "$_/libfree.a";
  }

  # if we get here, we go with the defaults again
  return ('/usr/local/lib',$include);
}

sub readline_setup {
  eval 'use Term::ReadLine' ;

  if ($@ eq '') {
    $::term = new Term::ReadLine 'AcePerl install';
    eval {
      sub main::_prompt {
	my ($prompt, $default) = @_ ;

	$_ = $::term -> readline ("$prompt: ",$default) ;
	s!^~(?=/|$)!$ENV{HOME}!;  # change ~/ into home directory
	s!^~([^/]+)!(getpwnam($1))[7]!e; # change ~foo into home directory
	if (!/^\s*$/) {
	  s/\s+$//;
	  return $_ ;
	}
	else {
	  if ($_ eq "") {
	    return $default ;
	  }
	  else {
	    return "" ; 
	  }
	}
      }
    };
    die $@ if $@;
    print "ReadLine support enabled\n" ;
  }
  else { 
    eval <<'EOT' ;
    sub main::_prompt {
      prompt(@_);
    }
EOT
  }
}

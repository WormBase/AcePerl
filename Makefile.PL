use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
readline_setup();
exit -1 unless
  $location = _prompt('Location of libace.a and libacecl.a','/usr/local/lib');
exit -1 unless
  $headers = _prompt('Location of aceclient.h','/usr/local/include');

WriteMakefile(
    'DISTNAME'     => 'AcePerl',
    'NAME'	   => 'Ace',
    'VERSION_FROM' => 'Ace.pm', # finds $VERSION
    'LIBS'	   => ["-L$location -lacecl -lace"],   # e.g., '-lm' 
    'DEFINE'	   => '',     # e.g., '-DHAVE_SOMETHING' 
    'OBJECT'    => '$(O_FILES)',
    'XSPROTOARG'   => '-noprototypes',
    'INC'	   => "-I$headers",     # e.g., '-I/usr/include/other' 
);

sub readline_setup {
  eval 'use Term::ReadLine' ;

  if ($@ eq '') {
    $::term = new Term::ReadLine 'AcePerl install';
    eval {
      sub main::_prompt {
	my ($prompt, $default) = @_ ;
	
	$_ = $::term -> readline ("$prompt [$default] ") ;
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

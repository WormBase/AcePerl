use ExtUtils::MakeMaker;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

$headers  = "./ace/wh";

WriteMakefile(
	      'DISTNAME'     => 'AcePerl',
	      'NAME'	     => 'Ace',
	      'VERSION_FROM' => 'Ace.pm', # finds $VERSION
	      'MYEXTLIB'     => 'ace/libaceperl.a',
	      'LIBS'         => ['-lc'],
	      'PMLIBDIRS'    => ['GFF','Ace'],
	      'DEFINE'	     => '',
	      'OBJECT'       => '$(O_FILES)',
	      'XSPROTOARG'   => '-noprototypes',
	      'INC'	     => "-I$headers",
	      'dist'         => {'COMPRESS'=>'gzip -9f', 
                                 'SUFFIX' => 'gz',
	                         'ZIP'=>'/usr/bin/zip','ZIPFLAGS'=>'-rl'
			      },
	      PL_FILES => {'make_docs.PL' => '.docs'},
	      'clean'        => {'FILES' => 'ace/lib* ace/*.o ace/rpcace*.[ch]'},
);

exit 0;

sub MY::postamble {
    my $definition = guess_definition();
    warn "Using $definition definitions to build ace library.\n";
"
\$(MYEXTLIB): ace/Makefile
	cd ace && \$(MAKE) ACEDB_MACHINE=$definition all
";
}

sub guess_definition {
    return $ENV{ACEDB_MACHINE} if $ENV{ACEDB_MACHINE};
    return uc $Config{osname};
}


use Config;
use ExtUtils::MakeMaker qw(prompt WriteMakefile);

my $choice;
while (!$choice) {
  $reply = prompt(
		  "\nWhat do you want to build?\n\n" .
		  "  1) Interface to Ace socket server and local databases (pure Perl)\n" .
		  "  2) The above plus XS optimizations (requires C compiler)\n" .
		  "  3) The above plus RPC server interface (requires C compiler)\n\n" .
		  "Enter your choice: ", "2");
  if ($reply =~ /(\d+)/) {
    $choice = $1;
    if ($choice < 1  ||  $choice > 3) {
      $choice = 0;
    }
  }
}
my @extlib = ();
push @extlib,'Freesubs' if $choice >= 2;
push @extlib,'RPC'      if $choice >= 3;

my $headers  = "./ace/wh";
WriteMakefile(
	      'DISTNAME'     => 'AcePerl',
	      'NAME'	     => 'Ace',
	      'VERSION_FROM' => 'Ace.pm', # finds $VERSION
	      'PMLIBDIRS'    => ['GFF','Ace'],
	      'DIR'          => \@extlib,
	      'DEFINE'	     => '',
	      'XSPROTOARG'   => '-noprototypes',
	      'INC'	     => "-I$headers",
	      'dist'         => {'COMPRESS'=>'gzip -9f', 
                                 'SUFFIX' => 'gz',
	                         'ZIP'=>'/usr/bin/zip','ZIPFLAGS'=>'-rl'
			      },
	      PL_FILES => {'make_docs.PL' => '.docs'},
	      'clean'        => {'FILES' => 'ace/lib* ace/*.o ace/rpcace*.[ch]'},
	      @libargs,
);

exit 0;


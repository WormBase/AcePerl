#!/usr/local/bin/perl

use Pod::Html;
mkdir "docs",0755;
mkdir "docs/Ace",0755;
foreach $pod ('Ace.pm',<Ace/*.pm>) {
  (my $out = $pod) =~ s/\.pm$/.html/;

  if (open(POD,"-|")) {
    open (OUT,">docs/$out");
    while (<POD>) {
      if (/<BODY>/) {
	print OUT <<END;
<BODY BGCOLOR="white">
<!--NAVBAR-->
<hr>
<a href="index.html">AcePerl Main Page</a>
END
;
      } else {
	print OUT;
      }
    }

  } else {  # child process
    pod2html(
	     $pod,
	     '--podroot=.',
	     '--podpath=.',
	     '--noindex',
	     '--htmlroot=/AcePerl/docs',
	     "--infile=$pod",
	     "--outfile=-"
	    );
    exit 0;
  }
}

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	   => 'Ace',
    'VERSION_FROM' => 'Ace.pm', # finds $VERSION
    'LIBS'	   => ['-L../ace/bin -lacecl -lace'],   # e.g., '-lm' 
    'DEFINE'	   => '',     # e.g., '-DHAVE_SOMETHING' 
    'XSPROTOARG'   => '-noprototypes',
    'INC'	   => '-I../ace/wh',     # e.g., '-I/usr/include/other' 
);

# Ace::Sequence::Homol is just like Ace::Object, but has start() and end() methods
package Ace::Sequence::Homol;

use vars '@ISA';
@ISA = 'Ace::Object';

use overload '""' => '_asString';

sub new {
  my ($pack,$db,$tclass,$tname,$start,$end) = @_;
  return unless my $obj = Ace::Object->new(-class=>$tclass,-name=>$tname,-db=>$db);
  @$obj{'start','end'} = ($start,$end);
  return bless $obj,$pack;
}

sub start  {  return $_[0]->{'start'};  }

sub end    {  return $_[0]->{'end'};    }

sub _asString { 
  my $n = $_[0]->name;
  "$n/$_[0]->{start}-$_[0]->{end}";
}


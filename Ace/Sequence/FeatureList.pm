package Ace::Sequence::FeatureList;

sub new {
  my $package =shift;
  my @lines = split("\n",$_[0]);
  my (%parsed);
  foreach (@lines) {
    next if m!^//!;
    my ($minor,$major,$count) = split "\t";
    next unless $count > 0;
    $parsed{$major}{$minor} = $count;
    $parsed{_TOTAL}++;
  }
  return bless \%parsed,$package;
}

# no arguments, scalar context -- count all features
# no arguments, array context  -- list of major types
# 1 argument, scalar context   -- count of major type
# 1 argument, array context    -- list of minor types
# 2 arguments                  -- count of subtype
sub types {
  my $self = shift;
  my ($type,$subtype) = @_;
  my $count = 0;

  unless ($type) {
    return wantarray ? grep !/^_/,keys %$self : $self->{_TOTAL};
  }

  unless ($subtype) {
    return keys %{$self->{$type}} if wantarray;
    foreach (keys %{$self->{$type}}) {
      $count += $self->{$type}{$_};
    }
    return $count;
  }
  
  return $self->{$type}{$subtype};
}

1;

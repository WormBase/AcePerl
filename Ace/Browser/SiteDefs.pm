package Ace::Browser::SiteDefs;

use CGI();
use Ace();

use strict;
use Carp;
use vars '$AUTOLOAD';
use constant SITE_DEFS => 'SiteDefs';

my %CONFIG;
my %CACHETIME;
my %CACHED;

sub getConfig {
  my $package = shift;
  my $name    = shift;
  die "Usage: getConfig(\$database_name)" unless defined $name;
  $package = ref $package if ref $package;
  my $file    = "${name}.pm";

  # make search relative to SiteDefs.pm file
  my $path = $package-> get_config || $package->resolvePath(SITE_DEFS . "/$file");

  return unless -r $path;
  return $CONFIG{$name} if exists $CONFIG{$name} and $CACHETIME{$name} >= (stat(_))[9];
  return unless $CONFIG{$name} = $package->_load($path);
  $CONFIG{$name}->{'name'} ||= $name;  # remember name
  $CACHETIME{$name} = (stat(_))[9];
  return $CONFIG{$name};
}

sub modtime {
  my $package = shift;
  my $name = shift;
  if (!$name && ref($package)) {
    $name = $package->Name;
  }
  return $CACHETIME{$name};
}

sub AUTOLOAD {
    my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    my $self = shift;
    croak "Unknown field \"$func_name\"" unless $func_name =~ /^[A-Z]/;
    return $self->{$func_name} = $_[0] if defined $_[0];
    return $self->{$func_name} if defined $self->{$func_name};
    # didn't find it, so get default
    return if (my $dflt = $pack->getConfig('default')) == $self;
    return $dflt->{$func_name};
}

sub DESTROY { }

sub map_url {
  my $self = shift;
  my ($display,$name,$class) = @_;
  $class ||= $name->class if ref($name) and $name->can('class');

  return unless my $code = $self->Url_mapper;
  my (@result,$url);
  if (@result = $code->($display,"$name",$class)) {
    return @result;
  }
  return unless @result = $self->getConfig('default')->Url_mapper->($display,"$name",$class);
  return unless $url = $self->display($result[0],'url');
  return ($url,$result[1]);
}

sub searches {
  my $self = shift;
  return unless my $s = $self->Searches;
  return @{$s} unless defined $_[0];
  return $self->Search_titles->{$_[0]};
}

# displays()                   => list of display names
# displays($name)              => hash reference for display
# displays($name=>$field)      => displays at {field}
sub display {
  my $self = shift;
  return unless my $d = $self->Displays;
  return keys %{$d}     unless defined $_[0];
  return                unless exists $d->{$_[0]}; 
  return $d->{$_[0]}    unless defined $_[1];
  return $d->{$_[0]}{$_[1]};
}

sub displays {
  my $self = shift;
  return unless my $d = $self->Classes;
  return keys %$d unless defined $_[0];
  my $type = ucfirst(lc($_[0]));
  return  unless exists $d->{$type};
  my $value = $d->{$type};
  if (ref $value eq 'CODE') { # oh, wow, a subroutine
    my @v = $value->();  # invoke to get list of displays
    return wantarray ? @v : \@v;
  } else {
    return  wantarray ? @{$value} : $value;
  }
}

sub class2displays {
  my $self = shift;
  # No class specified.  Return name of all defined classes.
  return $self->displays unless defined $_[0];

  # A class is specified.  Map it into the list of display records.
  my @displays = map {$self->display($_)} $self->displays($_[0]);
  return @displays;
}

sub _load {
  my $package = shift;
  my $file    = shift;
  no strict 'vars';
  no strict 'refs';

  $file =~ m!([/a-zA-Z0-9._-]+)!;
  my $safe = $1;

  (my $ns = $safe) =~ s/\W/_/g;
  my $namespace = __PACKAGE__ . '::Config::' . $ns;
  unless (eval "package $namespace; require '$safe';") {
    warn "compile error while parsing config file '$safe': $@\n";
  }
  # build the object up from the values compiled into the $namespace area
  my %data;

  # get the scalars
  local *symbol;
  foreach (keys %{"${namespace}::"}) {
    *symbol = ${"${namespace}::"}{$_};
    $data{ucfirst(lc $_)} = $symbol if defined($symbol);
    $data{ucfirst(lc $_)} = \%symbol if defined(%symbol);
    $data{ucfirst(lc $_)} = \@symbol if defined(@symbol);
    $data{ucfirst(lc $_)} = \&symbol if defined(&symbol);
    undef *symbol unless defined &symbol;  # conserve  some memory
  }

  # special case: get the search scripts as both an array and as a hash
  if (my @searches = @{"$namespace\:\:SEARCHES"}) {
    $data{Searches} = [ @searches[map {2*$_} (0..@searches/2-1)] ];
    %{$data{Search_titles}} = @searches;
  }

  # return this thing as a blessed object
  return bless \%data,$package;
}

sub resolvePath {
  my $pack = shift;
  my $file = shift;

  # if we're running under MOD_PERL, then look for the configuration file
  # underneath AceBrowserRoot configuration variable

  if (exists $ENV{MOD_PERL}) {
    my $r    = Apache->request;
    if (my $root = $r->dir_config('AceBrowserRoot')) {
      $file ||= '';
      return $CACHED{$file,$r->filename} if exists $CACHED{$file,$r->filename};
      return $CACHED{$file,$r->filename} = "$root/$file";
    }
  }

  # otherwise locate configuration file relative to this file, 
  # e.g. /usr/local/perl5/site_perl/Ace/Browser/SiteDefs/foo.pm
  (my $rpath = __PACKAGE__) =~ s{::}{/}g;
  warn "rpath = ${rpath}.pm";
  my $path = $INC{"${rpath}.pm"} || warn "Unexpected error: can't locate acebrowser SiteDefs.pm file";
  $path =~ s![^/]*$!!;  # trim to directory
  return "$path/$file";
}

sub get_config {
  my $pack = shift;
  my $file = shift;

  return unless exists $ENV{MOD_PERL};
  my $r    = Apache->request;
  return $r->dir_config('AceBrowserConf') ||
    $r->dir_config('AceBrowserRoot') . "/$file";
}


1;

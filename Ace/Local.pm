package Ace::Local;

require 5.004;

use IPC::Open2;
use Symbol;
use Fcntl qw/F_SETFL O_NONBLOCK/;

$VERSION = 1.00;

use Ace qw/rearrange STATUS_WAITING STATUS_PENDING STATUS_ERROR/;
use constant DEFAULT_HOST=>'localhost';
use constant DEFAULT_PORT=>200005;
use constant DEFAULT_DB=>'/usr/local/acedb';

sub connect {
  my $class = shift;
  my ($path,$program,$host,$port) = rearrange([PATH,PROGRAM,HOST,PORT],@_);
  my $args;
  
  # some pretty insane heuristics to handle BOTH tace and aceclient
  die "Specify either -path or -host and -port" if ($program && ($host || $port));
  die "-path is not relevant for aceclient, use -host and/or -port"
    if $program=~/aceclient/ && $path;
  die "-host and -port are not relevant for tace, use -path"
    if $program=~/tace/ and ($port || $host);
  
  # note, this relies on the programs being included in the current PATH
  if ($host || $port) {
    $program ||= 'aceclient';
  } else {
    $program ||= 'tace';
  }
  if ($program =~ /aceclient/) {
    $host ||= DEFAULT_HOST;
    $port ||= DEFAULT_PORT;
    $args = "$host -port $port";
  } else {
    $path ||= DEFAULT_DB;
    $path = _expand_twiddles($path);
    $args = $path;
  }
  
  my($rdr,$wtr) = (gensym,gensym);
  my($pid) = open2($rdr,$wtr,"$program $args");
  unless ($pid) {
    $ACE::ERR = <$rdr>;
    return undef;
  }

  # Figure out the prompt by reading until we get zero length,
  # then take whatever's at the end.
  local($/) = "> ";
  my $data = <$rdr>;
  my ($prompt) = $data=~/^(.+> )/m;
  unless ($prompt) {
    $ACE::ERR = "$program didn't open correctly";
    return undef;
  }

  # set nonblocking reads
  fcntl($rdr,F_SETFL,O_NONBLOCK);

  return bless {
		'read'   => $rdr,
		'write'  => $wtr,
		'prompt' => $prompt,
		'pid'    => $pid,
		'status' => STATUS_WAITING,
	       },$class;
}

sub DESTROY {
  my $self = shift;
  # just for paranoid reasons. shouldn't be necessary
  close $self->{'write'} if $self->{'write'};  
  close $self->{'read'} if $self->{'read'};
  waitpid($self->{pid},0) if $self->{'pid'};
}

sub encore {
  my $self = shift;
  return $self->status == STATUS_PENDING;
}

sub status {
  return $_[0]->{'status'};
}

sub error {
  my $self = shift;
  return $self->{'error'};
}

sub query {
  my $self = shift;
  my $query = shift;
  return undef if $self->{'status'} == STATUS_ERROR;
  do $self->read() until $self->{'status'} != STATUS_PENDING;
  my $wtr = $self->{'write'};
  print $wtr "$query\n";
  $self->{'status'} = STATUS_PENDING;
}

sub read {
  my $self = shift;
  return undef unless $self->{'status'} = STATUS_PENDING;
  my $rdr = $self->{'read'};
  while (1) {
    my $data;
    my $bytes = read($rdr,$data,2048);
    $self->{'buffer'} .= $data;

    # return partial results for paragraph breaks
    if ($self->{'buffer'} =~ /\A.*\n\n/s) {
      next unless $&;
      $self->{'buffer'} = $';
      return $&;
    }

    if ($self->{'buffer'}=~/$self->{'prompt'}/so) {
      $self->{'status'} = STATUS_WAITING;
      $self->{'buffer'} = '';
      return $`;
    }
  }

  # never get here
}

# expand ~foo syntax
sub _expand_twiddles {
  my $path = shift;
  my ($to_expand,$homedir);
  return $path unless $path =~ m!^~([^/]*)!;

  if ($to_expand = $1) {
    $homedir = (getpwnam($to_expand))[7];
  } else {
    $homedir = (getpwuid($<))[7];
  }
  return $path unless $homedir;

  $path =~ s!^~[^/]*!$homedir!;
  return $path;
}

__END__

=head1 NAME

Ace::Local - use tace or aceclient to open a local connection to an Ace database

=head1 SYNOPSIS

  use Ace::Local
  my $ace = Ace::Local->connect(-path=>'/usr/local/acedb/elegans');
  $ace->query('find author Se*');
  die "Query unsuccessful" unless $ace->status;
  $ace->query('show');
  while ($ace->encore) {
    print $ace->read;
  }

=head1 DESCRIPTION

This class is provided for low-level access to local (non-networked)
Ace databases via the I<tace> program.  You will generally not need to
access it directly.  Use Ace.pm instead.

For the sake of completeness, the method can also use the I<aceclient>
program for its access.  However the Ace::AceDB class is more efficient
for this purpose.

=head1 METHODS

=head2 connect()

  $accessor = Ace::Local->connect(-path=>$path_to_database);

Connect to the database at the indicated path using I<tace> and return
a connection object (an "accessor").  I<Tace> must be on the current
search path.  Multiple accessors may be open simultaneously.

Arguments include:

=over 4

=item B<-path>

Path to the database (location of the "wspec/" directory).

=item B<-program>

Used to indicate the location of the desired I<tace> or I<aceclient>
executable.  Can be used to override the search path.

=item B<-host>

Used when invoking I<aceclient>.  Indicates the host to connect to.

=item B<-port>

Used when invoking I<aceclient>.  Indicates the port to connect to.

=back

=head2 query()

  $status = $accessor->query('query string');

Send the query string to the server and return a true value if
successful.  You must then call read() repeatedly in order to fetch
the query result.

=head2 read()

Read the result from the last query sent to the server and return it
as a string.  ACE may return the result in pieces, breaking between
whole objects.  You may need to read repeatedly in order to fetch the
entire result.  Canonical example:

  $accessor->query("find Sequence D*");
  die "Got an error ",$accessor->error() if $accessor->status == STATUS_ERROR;
  while ($accessor->status == STATUS_PENDING) {
     $result .= $accessor->read;
  }

=head2 status()

Return the status code from the last operation.  Status codes are
exported by default when you B<use> Ace.pm.  The status codes you may
see are:

  STATUS_WAITING    The server is waiting for a query.
  STATUS_PENDING    A query has been sent and Ace is waiting for
                    you to read() the result.
  STATUS_ERROR      A communications or syntax error has occurred

=head2 error()

May return a more detailed error code supplied by Ace.  Error checking
is not fully implemented.

=head2 encore()

This method will return true after you have performed one or more
read() operations, and indicates that there is more data to read.
B<encore()> is functionally equivalent to:

   $encore = $accessor->status == STATUS_PENDING;

In fact, this is how it's implemented.

=head1 SEE ALSO

Ace(1)

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1997-1998, Lincoln D. Stein

This library is free software; 
you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut
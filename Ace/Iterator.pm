package Ace::Iterator;
use strict;
use vars '$VERSION';
use Carp;
use Ace 1.50 qw(rearrange);

$VERSION = '1.50';

sub new {
  my $pack = shift; 
  my ($db,$query,$filled,$chunksize) = rearrange([qw/DB QUERY FILLED CHUNKSIZE/],@_);
  my $self = {
	      'db'    => $db,
	      'query' => $query,
	      'valid' => undef,
	      'cached_answers' => [],
	      'filled' => ($filled || 0),
	      'chunksize' => ($chunksize || 40),
	      'current' => 0
	     };
  $db->_register_iterator($self) if $db && ref($db);
  return bless $self,$pack;
}

sub next {
  my $self = shift;
  $self->_fill_cache() unless @{$self->{'cached_answers'}};
  my $cache = $self->{'cached_answers'};
  my $result = shift @{$cache};
  $self->{'current'}++;
  $self->{'db'}->_unregister_iterator unless $result;
  return $result;
}

sub _invalidate {
  my $self = shift;
  undef $self->{'valid'};
}

# Fill up cache for iterator
sub _fill_cache {
  my $self = shift;
  my $db = $self->{'db'};
  $db->_query($self->{'query'}) unless $self->{'valid'};
  my @objects = $self->{'filled'} ? $db->_fetch($self->{'chunksize'},$self->{'current'}) :
                                    $db->_list($self->{'chunksize'},$self->{'current'});
  $self->{'valid'}++;
  $self->{'cached_answers'} = \@objects;
}

1;

__END__


=head1 NAME

Ace::Iterator - Iterate Across an ACEDB Query

=head1 SYNOPSIS

    use Ace;
    $db = Ace->connect(-host => 'beta.crbm.cnrs-mop.fr',
                       -port => 20000100);

    $i  = $db->fetch_many(Sequence=>'*');  # fetch a cursor
    while ($obj = $i->next) {
       print $obj->asTable;
    }


=head1 DESCRIPTION

The Ace::Iterator class implements a persistent query on an Ace
database.  You can create multiple simultaneous queries and retrieve
objects from each one independently of the others.  This is useful
when a query is expected to return more objects than can easily fit
into memory.  The iterator is essentially a database "cursor."

=head2 new() Method

  $iterator = Ace::Iterator->new(-db        => $db,
                                 -query     => $query,
                                 -filled    => $filled,
                                 -chunksize => $chunksize);

An Ace::Iterator is returned by the Ace accessor's object's
fetch_many() method. You usually will not have cause to call the new()
method directly.  If you do so, the parameters are as follows:

=over 4

=item -db

The Ace database accessor object to use.

=item -query

A query, written in Ace query language, to pass to the database.  This
query should return a list of objects.

=item -filled

If true, then retrieve complete objects from the database, rather than
empty object stubs.  Retrieving filled objects uses more memory and
network bandwidth than retrieving unfilled objects, but it's
recommended if you know in advance that you will be accessing most or
all of the objects' fields, for example, for the purposes of
displaying the objects.

=item -chunksize

The iterator will fetch objects from the database in chunks controlled
by this argument.  The default is 40.  You may want to tune the
chunksize to optimize the retrieval for your application.

=back

=head2 next() method

  $object = $iterator->next;

This method retrieves the next object from the query, performing
whatever database accesses it needs.  After the last object has been
fetched, the next() will return undef.  Usually you will call next()
inside a loop like this:

  while (my $object = $iterator->next) {
     # do something with $object
  }

Because of the way that object caching works, next() will be most
efficient if you are only looping over one iterator at a time.
Although parallel access will work correctly, it will be less
efficient than serial access.  If possible, avoid this type of code:

  my $iterator1 = $db->fetch_many(-query=>$query1);
  my $iterator2 = $db->fetch_many(-query=>$query2);
  do {
     my $object1 = $iterator1->next;
     my $object2 = $iterator2->next;
  } while $object1 && $object2;

=head1 SEE ALSO

L<Ace>, L<Ace::Model>, L<Ace::Object>

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1997-1998 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut


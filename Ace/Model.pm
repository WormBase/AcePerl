package Ace::Model;
# file: Ace/Model.pm
# This is really just a placeholder class.  It doesn't do  anything interesting.
use strict;
use overload
  '""' => 'asString',
  fallback => 'TRUE';

# construct a new Ace::Model
sub new {
  my $class = shift;
  my $data = shift;
  $data=~s!\s+//.*$!!gm;  # remove all comments
  $data=~s!\0!!g;
  my ($name) = $data=~/\A\?(\w+)/;
  return bless { 
		name => $name,
		raw => $data,
	       },$class;
}

sub name {
  return shift()->{name};
}

# return all the tags in the model as a hashref.
# in a list context returns the tags as a long list result
sub tags {
  my $self = shift;
  $self->{tags} ||= { map {lc($_)=>1}
		      grep(!/^\?|^\#|XREF|UNIQUE|ANY|FREE|REPEAT|Int|Text|Float|DateType/,
			   $self->{raw}=~m/(\S+)/g)
		    };
  return wantarray ? keys %{$self->{tags}} : $self->{tags};
}

# return true if the tag is a valid one
sub valid_tag {
  my $self = shift;
  my $tag = lc shift;
  return $self->tags->{$tag};
}

# just return the model as a string
sub asString {
  return shift()->{'raw'};
}

1;

__END__

=head1 NAME

Ace::Model - Get information about AceDB models

=head1 SYNOPSIS

  use Ace;
  my $db = Ace->connect(-path=>'/usr/local/acedb/elegans');
  my $model = $db->model('Author');
  print $model;
  $name = $model->name;
  @tags = $model->tags;
  print "Paper is a valid tag" if $model->valid_tag('Paper');

=head1 DESCRIPTION

This class is provided for access to AceDB class models.  It provides
the model in human-readable form, and does some limited but useful
parsing on your behalf.  

Ace::Model objects are obtained either by calling an Ace database
handle's model() method to retrieve the model of a named class, or by
calling an Ace::Object's model() method to retrieve the object's
particular model.

=head1 METHODS

=head2 new()

  $model = Ace::Model->new($model_data);

This is a constructor intended only for use by Ace and Ace::Object
classes.  It constructs a new Ace::Model object from the raw string
data in models.wrm.

=head2 name()

  $name = $model->name;

This returns the class name for the model.

=head2 tags()

   @tags = $model->tags;

This returns a list of all the valid tags in the model.

=head2 valid_tag()

   $boolean  = $model->valid_tag($tag);

This returns true if the given tag is part of the model.

=head2 asString()

   print $model->asString;

asString() returns the human-readable representation of the model with
comments stripped out.  Internally this method is called to
automatically convert the model into a string when appropriate.  You
need only to start performing string operations on the model object in
order to convert it into a string automatically:

   print "Paper is unique" if $model=~/Paper ?Paper UNIQUE/;

=head1 SEE ALSO

L<Ace>

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1997-1998, Lincoln D. Stein

This library is free software; 
you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut



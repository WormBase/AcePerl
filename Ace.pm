package Ace;

use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $AUTOLOAD);

require Exporter;
require DynaLoader;

@ISA = qw(Exporter DynaLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	ACE_INVALID
	ACE_OUTOFCONTEXT
	ACE_SYNTAXERROR
	ACE_UNRECOGNIZED
	STATUS_WAITING
        STATUS_PENDING
	STATUS_ERROR
);
@EXPORT_OK = qw(
		rearrange
		);
$VERSION = '1.36';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
		croak "Your vendor has not defined Ace macro $constname";
	}
    }
    eval "sub $AUTOLOAD { $val }";
    goto &$AUTOLOAD;
}

bootstrap Ace $VERSION;

# Preloaded methods go here.
use vars qw/$ERR/;

sub connect {
    my $class = shift;
    my ($host,$port,$path,$program,$objclass) = 
      rearrange(['HOST','PORT','PATH','PROGRAM','CLASS'],@_);
    $host ||= 'localhost';
    $port ||= 23456;

    my $database;

    # open up a connection to a local database
    if ($path || $program) {
      require Ace::Local;
      $database = Ace::Local->connect(@_);
    } else {
      $database = Ace::AceDB->new($host,$port);
    }
    unless ($database) {
	$ACE::ERR = "Couldn't open database";
	return undef;
    }

    my $self = bless {
		      'database'=> $database,
		      'host'   => $host,
		      'port'   => $port,
		      'class'  => $objclass || 'Ace::Object',
		      'date_style' => 'java'
    },$class;
    return $self;
}

# Return true if the database is still connected.  This is oddly convoluted
# because there are numerous things that can go wrong, including:
#   1. server has gone away
#   2. server has timed out our connection! (grrrrr)
#   3. communications channel contains unread garbage and is in an inconsistent state
sub ping {
  my $self = shift;
  local($SIG{PIPE})='IGNORE';  # so we don't get a fatal exception during the check
  my $result = $self->raw_query('');
  return undef unless $result;  # server has gone away
  return undef if $result=~/broken connection|client time out/;  # server has timed us out  
  return undef unless $self->{database}->status() == STATUS_WAITING(); #communications oddness
  return 1;
}

# Return the low-level Ace::AceDB object
sub db {
  return $_[0]->{'database'};
}

# Create a new Ace::Object in the indicated database
# (doesn't actually write into database until you do a commit)
sub new (\$$$) {
  my $self = shift;
  my ($class,$name) = rearrange([qw/class name/],@_);
  return undef if $self->fetch($class,$name);
  return $self->{'class'}->new($class,$name,$self);
}

# Set or retrieve the display style for dates
sub date_style (\$;$) {
  my $self = shift;
  $self->{'date_style'} = $_[0] if defined($_[0]);
  return $self->{'date_style'};
} 

# Fetch one or a group of objects from the database
sub fetch {
  my $self = shift;
  my ($class,$pattern,$count,$offset,$filled) = 
    rearrange(['CLASS',['NAME','PATTERN'],'COUNT','OFFSET',['FILL','FILLED']],@_);
  ($offset,$count) = (0,-1) unless defined $count;
  $count = 1 unless wantarray;
  $self->_query(qq{query find $class "$pattern"});
  my (@h) = $filled ? $self->_fetch($count,$offset) : $self->_list($count,$offset);
  return wantarray ? @h : $h[0];
}

# Perform an ace query and return the result
sub find {
  my $self = shift;
  my ($query,$count,$offset,$filled) = rearrange(['QUERY','COUNT','OFFSET',['FILL','FILLED']],@_);
  ($offset,$count) = (0,-1) unless defined $count;
  $count = 1 unless wantarray;
  $query = "find $query" unless $query=~/^find/i;
  $self->_query("query $query");
  my (@h) = $filled ? $self->_fetch($count,$offset) : $self->_filled($count,$offset);
  return wantarray ? @h : $h[0];
}

# Fetch many objects in iterative style
sub fetch_many {
  my $self = shift;
  my ($class,$pattern) = rearrange(['CLASS',['PATTERN','NAME']],@_);
  my $iterator = Ace::Iterator->new($self,"find $class $pattern");
  $self->_register_iterator($iterator);
  return $iterator;
}

# Find many objects in iterative style
sub find_many {
  my $self = shift;
  my ($query) = rearrange(['QUERY'],@_);
  $query = "find $query" unless $query=~/^find/i;
  my $iterator = Ace::Iterator->new($self,"query $query");
  $self->_register_iterator($iterator);
  return $iterator;
}

# Obtain a listing of the objects matching pattern.
sub list {
    my ($self,$class,$pattern,$count,$offset) = @_;
    my @result;
    $self->raw_query("find $class $pattern");
    $self->_list($count,$offset);
}

# Count the objects matching pattern without fetching them.
sub count {
    my ($self,$class,$pattern) = @_;
    undef $ERR;

    $pattern =~ tr/\n//d;
    $pattern ||= '*';
    my $result = $self->raw_query("find $class $pattern");
    unless ($result =~ /Found (\d+) objects/m) {
	$ERR = 'Unexpected close during find';
	return undef;
    }

    return $1;
}

#########################################################
# These functions are for low-level (non OO) access only.
sub pick {
    my ($self,$class,$item) = @_;
    undef $ERR;
    return () unless $self->count($class,$item) == 1;

    # if we get here, then we've got some data to return.
    # yes, we're repeating code slightly...
    my @result;
    my $result = $self->raw_query("show -j");
    unless ($result =~ /(\d+) object dumped/m) {
	$ERR = 'Unexpected close during pick';
	return undef;
    }

    @result = grep (!m!^//!,split("\n\n",$result));
    return $result[0];
}

# This is for low-level access only.
sub show {
    my ($self,$class,$pattern,$tag) = @_;
    undef $ERR;
    return () unless $self->count($class,$pattern);
    
    # if we get here, then we've got some data to return.
    my @result;
    my $result = $self->raw_query("show -j $tag");
    unless ($result =~ /(\d+) object dumped/m) {
	$ERR = 'Unexpected close during show';
	return undef;
    }
    return grep (!m!^//!,split("\n\n",$result));
}

sub read_object {
    my $self = shift;
    return undef unless $self->{database};
    my $result;
    while ($self->{database}->status == STATUS_PENDING()) {
      $result .= $self->{database}->read() ;
    }
    return $result;
}

# do a query, and return the result immediately
sub raw_query {
    my ($self,$query) = @_;
    $self->{database}->query($query);
    $self->_alert_iterators;
    return $self->read_object;
}

# Return a list of all the classes known to the server.
sub classes {
  my ($self,$invisible) = @_;
  my $query = defined($invisible) && $invisible ?
    "query find class !buried" 
      :
    "query find class visible !buried";
  $self->_alert_iterators;
  $self->_query($query);
  return $self->_list;
}

# return the last error
sub error {
    return $ACE::ERR;
}

#####################################################################
###################### private routines #############################
sub rearrange {
    my($order,@param) = @_;
    return () unless @param;
    
    return @param unless (defined($param[0]) && substr($param[0],0,1) eq '-');

    my $i;
    for ($i=0;$i<@param;$i+=2) {
        $param[$i]=~s/^\-//;     # get rid of initial - if present
        $param[$i]=~tr/a-z/A-Z/; # parameters are upper case
    }
    
    my(%param) = @param;                # convert into associative array
    my(@return_array);
    
    local($^W) = 0;
    my($key)='';
    foreach $key (@$order) {
        my($value);
        if (ref($key) eq 'ARRAY') {
            foreach (@$key) {
                last if defined($value);
                $value = $param{$_};
                delete $param{$_};
            }
        } else {
            $value = $param{$key};
            delete $param{$key};
        }
        push(@return_array,$value);
    }
    push (@return_array,{%param}) if %param;
    return @return_array;
}

# do a query, but don't return the result
sub _query {
  my ($self,$query) = @_;
  $self->_alert_iterators;
  $self->{'database'}->query($query);
}

# return a portion of the active list
sub _list {
  my $self = shift;
  my ($count,$offset) = @_;
  ($offset,$count) = (0,-1) unless $count;
  my (@result);
  my $result = $self->raw_query("list -j -b $offset -c $count");
  while ($result =~ /\?(\w+)\?(.+)\?$/mg) {
    push(@result,$self->{'class'}->new($1,$2,$self));
  }
  return @result;
}

# return a portion of the active list
sub _fetch {
  my $self = shift;
  my ($count,$start) = @_;
  my (@result);
  ($start,$count) = (0,-1) unless $count;
  $self->{database}->query("show -j -b $start -c $count");
  while (my @objects = $self->_fetch_chunk) {
    push (@result,@objects);
  }
  return wantarray ? @result : $result[0];
}

sub _fetch_chunk {
  my $self = shift;
  return () unless $self->{database}->status == STATUS_PENDING();
  my $result = $self->{database}->read();
  my @chunks = split("\n\n",$result);
  my @result;
  foreach (@chunks) {
    next if m!^//!;
    next unless /\S/;  # f**ing     appears every so often!
    push(@result,$self->{'class'}->newFromText($_,$self));
  }
  return @result;
}

sub _register_iterator {
  my ($self,$iterator) = @_;
  $self->{'iterators'}->{$iterator} = $iterator;
}

sub _unregister_iterator {
  my ($self,$iterator) = @_;
  delete $self->{'iterators'}->{$iterator};
}

sub _alert_iterators {
  my $self = shift;
  foreach (keys %{$self->{'iterators'}}) {
    $self->{'iterators'}->{$_}->invalidate;
  }
}

##########################################################################
##########################################################################
package Ace::Iterator;

sub new {
  my ($pack,$db,$query) = @_;
  my $self = {
	      'db'    => $db,
	      'query' => $query,
	      'valid' => undef,
	      'cached_answers' => [],
	      'current' => 0
	     };
  return bless $self,$pack;
}

sub invalidate {
  my $self = shift;
  undef $self->{'valid'};
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

sub _fill_cache {
  my $self = shift;
  if (!$self->{'valid'}) {
    $self->{'db'}->_query($self->{'query'});
    $self->{'db'}->_query("show -j -b $self->{'current'} -c -1");
    $self->{'valid'}++;
  }
  my @objects = $self->{'db'}->_fetch_chunk;
  $self->{'cached_answers'} = \@objects;
}

##########################################################################
##########################################################################
package Ace::Object;
use Carp;

use overload 
    '""'       => 'name',
    'fallback' =>' TRUE';
use vars qw($AUTOLOAD $DEFAULT_WIDTH $SPLIT_PATTERN %MO);

$DEFAULT_WIDTH=25;  # column width for pretty-printing
$SPLIT_PATTERN='\?([^?]*)\?([^?]*)\?';

# Pseudonyms and deprecated methods.
*isClass        =   \&isObject;
*pick = *follow = \&fetch;
*rearrange      = \&Ace::rearrange;

sub AUTOLOAD {
    my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    my $self = shift;
    if ($func_name =~/__/) {
      $func_name =~ s/__/./g;
      return $self->at($func_name,@_);
    }
    return $self->search($func_name,@_);
}

sub DESTROY { }

###################### object constructor #################
sub new ($$$;\$) {
  my $pack = shift;
  my($class,$name,$db) = rearrange([qw/class name/,[qw/database db/]],@_);
    $pack = ref($pack) if ref($pack);
    my $self = bless { 'name'  =>  $name,
		       'class' =>  $class
		       },$pack;
    $self->{'db'} = $db if $self->isObject;
    return $self
}

######### construct object from serialized input, not usually called directly ########
sub newFromText ($$;$) {
  my ($pack,$text,$db) = @_;
  $pack = ref($pack) if ref($pack);
  my @array;
  foreach (split("\n",$text)) {
    next unless $_;
    push(@array,[split("\t")]);
  }
  my $obj = $pack->_fromRaw(\@array,0,0,$#array,$db);
  $obj;
}


################### name of the object #################
sub name (\$) {
    my $self = shift;
    $self->{name} = shift if  defined($_[0]);
    return $self->_ace_format($self->{'class'},$self->{'name'});
}

################### class of the object #################
sub class (\$) {
    my $self = shift;
    defined($_[0])
	? $self->{class} = shift
	: $self->{class};
}

################### handle to ace database #################
sub db (\$) {
    my $self = shift;
    defined($_[0])
	? $self->{db} = shift
	: $self->{db};
}

### Return list of all the tags in the object ###
sub tags (\$){
    my $self = shift;
    my $current = $self->right;
    my @tags;
    while ($current) {
	push(@tags,$current);
	$current = $current->down;
    }
    return @tags;
}

### Return a portion of the tree at the indicated tag path     ###
#### In a list context returns the column.  In an array context ###
#### returns a pointer to the subtree ####
#### Usually returns what is pointed to by the tag.  Will return
#### the parent object if you pass a true value as the second argument
sub at (\$;$$) {
    my $self = shift;
    my($tag,$return_parent,$pos) = rearrange(['TAG','PARENT','POS'],@_);
    return $self->right unless $tag;

    if (!defined($pos) and $tag=~/\[(\d+)\]$/) {
      $pos = $1;
      $tag=$`;
    }

    my $o = $self;
    my ($parent,$above,$left);
    $tag =~ s/\\\./$;/g; # protect backslashed dots
    my (@tags) = split(/\./,$tag);
    foreach $tag (@tags) {
      $tag=~s/$;/./g; # unprotect backslashed dots
      my $p = $o;
      ($o,$above,$left) = $o->_at($tag);
      return () unless $o;
    }
    return $above || $left if $return_parent;
    return defined $pos ? $o->right($pos) : $o unless wantarray;
    return $o->col($pos);
}

### Flatten out part of the tree into an array ####
### along the row.  Will not follow object references.  ###
sub row (\$;$) {
  my $self = shift;
  my $pos = shift;
  my @r;
  my $o = defined $pos ? $self->right($pos) : $self;
  while ($o) {
    push(@r,$o);
    $o = $o->right;
  }
  return @r;
}

### Flatten out part of the tree into an array ####
### along the column. Will not follow object references. ###
sub col (\$;$) {
  my $self = shift;
  my $pos = shift;
  $pos = 1 unless defined $pos;
  croak "Position must be positive" unless $pos >= 0;

  return ($self) unless $pos > 0;

  my @r;
  # This is for tag[1] semantics
  if ($pos == 1) {
    for (my $o=$self->right; $o; $o=$o->down) {
      push (@r,$o);
    }
  } else {
    # This is for tag[2] semantics
    for (my $o=$self->right; $o; $o=$o->down) {
      next unless my $right = $o->right($pos-2);
      push (@r,$right->col);
    }
  }
  return @r;
}

#### Search for a tag, and return the column ####
#### Uses a breadth-first search (cols then rows) ####
sub search (\$$;$$) {
    my ($self,$tag,$pos) = @_;

    TRY: {
	last TRY if exists $self->{'.PATHS'}->{$tag};

	# If the object hasn't been filled already, then we can use
	# acedb's query mechanism to fetch the subobject.  This is a
	# big win for large objects.
	unless ($self->filled) {
	  my $subobject = $self->newFromText(
					     $self->{'db'}->show($self->class,$self->name,$tag),
					     $self->{'db'}
					    );
	  if ($subobject) {
	    my $obj = $self->new('tag',$tag,$self->{'db'});
	    $obj->{'right'} = $subobject->right;
	    $self->{'.PATHS'}->{$tag} = $obj;
	  } else {
	    $self->{'.PATHS'}->{$tag} = undef;
	  }
	  last TRY;
	}
	
	my @col = $self->col;
	foreach (@col) {
	  next unless $_->isTag;
	  if ($_ eq $tag) {
	    $self->{'.PATHS'}->{$tag} = $_;
	    last TRY;
	  }
	}

	# if we get here, we didn't find it in the column,
	# so we call ourselves recursively to find it
	foreach (@col) {
	  next unless $_->isTag;
	  if (my $r = $_->search($tag)) {
	    $self->{'.PATHS'}->{$tag} = $r;	
	    last TRY;
	  }
	}

	# If we got here, we didn't find it.  So tag the cache
	# as empty.
	$self->{'.PATHS'}->{$tag} = undef;
      }

    my $t = $self->{'.PATHS'}->{$tag};
    return wantarray ? () : undef  unless $t;
    return defined $pos ? $t->right($pos) : $t  unless wantarray;

    # We do something verrrry interesting in an array context.
    # If no position is defined, we return the column to the right.
    # If a position is defined, we return everything $POS tags
    # to the right (so-called tag[2] system).
    return $t->col($pos);
}

#### return true if tree is populated, without populating it #####
sub filled (\$) {
  my $self = shift;
  return exists($self->{'right'}) || exists($self->{'raw'});
}

#### return true if you can follow the object in the database (i.e. a class ###
sub isPickable (\$) {
    return shift->isObject;
}

#### Return a string representation of the object subject to Ace escaping rules ###
sub escape (\$){
  my $self = shift;
  my $name = $self->name;
  my $needs_escaping = $name=~/[^\w.-]/ || $self->isClass;
  return $name unless $needs_escaping;
  $name=~s/\"/\\"/g; #escape quotes"
  return qq/"$name"/;
}


### Return the pretty-printed HTML table representation ###
### may pass a code reference to add additional formatting to cells ###
sub asHTML (\$;$$) {
    my $self = shift;
    my ($modify_code) = rearrange(['MODIFY'],@_);
    return undef unless $self->right;
    my $string = "<TABLE BORDER>\n<TR ALIGN=LEFT VALIGN=TOP><TH>$self</TH>";
    $modify_code = \&_default_makeHTML unless $modify_code;
    $self->right->_asHTML(\$string,1,2,$modify_code);
    $string .= "</TR>\n</TABLE>";
    return $string;
}


#### As tab-delimited table ####
sub asTable (\$) {
    my $self = shift;
    my $string = "$self\t";
    my $right = $self->right;
    $right->_asTable(\$string,1,2) if $right;
    return $string . "\n";
}

#### In "ace" format ####
sub asAce (\$) {
  my $self = shift;
  my $string = '';
  $self->right->_asAce(\$string,0,[]);
  "$string\n";
}

### Pretty-printed version ###
sub asString {
  my $self = shift;
  my $MAXWIDTH = shift || $DEFAULT_WIDTH;
  my $tabs = $self->asTable;
  return "$self" unless $tabs;
  my(@lines) = split("\n",$tabs);
  my($result,@max);
  foreach (@lines) {
    my(@fields) = split("\t");
    for (my $i=0;$i<@fields;$i++) {
      $max[$i] = length($fields[$i]) if
	!defined($max[$i]) or $max[$i] < length($fields[$i]);
    }
  }
  foreach (@max) { $_ = $MAXWIDTH if $_ > $MAXWIDTH; } # crunch long lines
  my $format1 = join(' ',map { "^"."<"x $max[$_] } (0..$#max)) . "\n";
  my $format2 =   ' ' . join('  ',map { "^"."<"x ($max[$_]-1) } (0..$#max)) . "~~\n";
  $^A = '';
  foreach (@lines) {
    my @data = split("\t");
    push(@data,('')x(@max-@data));
    formline ($format1,@data);
    formline ($format2,@data);
  }
  return ($result = $^A,$^A='')[0];
}

# run a series of GIF commands and return the Gif and the semi-parsed
# "boxes" structure.  Commands is typically a series of mouseclicks
# ($gif,$boxes) = $aceObject->asGif(-clicks=>[[$x1,$y1],[$x2,$y2]...],
#                                   -dimensions=>[$x,$y]);
sub asGif {
  my $self = shift;
  my ($clicks,$dimensions) = rearrange(['CLICKS',['DIMENSIONS','DIM']],@_);
  my @commands = "gif display @{[$self->class]} \"@{[$self->name]}\"";
  unshift (@commands,"Dimensions @$dimensions") if ref($dimensions);
  push(@commands,map { "mouseclick @{$_}" } @$clicks) if ref($clicks);
  push(@commands,"gifdump -");
  
  # do the query
  my $data = $self->{'db'}->raw_query(join(' ; ',@commands));

  # did this query succeed?
  return () unless $data=~m!^// (\d+) bytes\n!m;
  my $bytes = $1;
  my $trim = $';  # everything after the match
  my $gif = substr($trim,0,$bytes);
  
  # now process the boxes
  my @b;
  my @boxes = split("\n",substr($trim,$bytes));
  foreach (@boxes) {
    last if m!^//!;
    chomp;
    my ($left,$top,$right,$bottom,$class,$name,$comments) = 
      m/^\s*\d*\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\w+):"(.+)"\s*(.*)/;
    next unless defined $left;
    $comments=~s/\s+$//; # sometimes there's extra white space at the end
    my $box = {'coordinates'=>[$left,$top,$right,$bottom],
	       'class'=>$class,
	       'name' =>$name,
	       'comment'=>$comments};
    push (@b,$box);
  }
  return ($gif,\@b);
}


############### object on the right of the tree #############
sub right (\$;$) {
  my ($self,$pos) = @_;

  $self->_fill;
  $self->_parse;
  return $self->{'right'} unless defined $pos;
  croak "Position must be positive" unless $pos >= 0;

  my $node = $self;
  while ($pos--) {
    $node = $node->right or return undef;
  }
  $node;
}

################# object below on the tree #################
sub down (\$) {
  my $self = shift;
  $self->_parse;
  return $self->{'down'};
}

################# delete a portion of the tree #############
# Only changes local copy until you perform commit() #
#  returns true if this is a valid thing to do.
sub delete (\$$;$) {
  my $self = shift;
  my($tag,$oldvalue) = rearrange([['TAG','PATH'],['VALUE','OLDVALUE','OLD']],@_);
  my $subtree = $self->at(($oldvalue ? "$tag.$oldvalue" : $tag),1);  # returns the parent
  if (defined($oldvalue) 
      && defined($subtree->{'right'})
      && "$subtree->{'right'}" eq $oldvalue) {
    $subtree->{'right'} = $subtree->{'right'}->down;
  } else {
    $subtree->{'down'} = $subtree->{'down'}->{'down'}
  }
  $oldvalue = '' unless defined($oldvalue);
  $oldvalue =~ s/([^a-zA-Z0-9_-])/\\$1/g;
  push(@{$self->{'delete'}},join(' ',split('\.',$tag),$oldvalue));
  delete $self->{'.PATHS'}; # uncache cached values
  1;
}

#############################################
#  follow into database #
sub fetch (\$;$) {
    my $self = shift;
    my $tag = shift;
    $self = $self->search($tag) or return undef
      if defined $tag;
    my $thing_to_pick = ($self->class eq 'tag' && $self->right) ? $self->right : $self;
    return $thing_to_pick->_clone;
}

# returns true if the object has a Model, i.e, can be followed into
# the database.
sub isObject {
    my $self = shift;
    return _isObject($self->class);
    1;
}

# returns true if the object is a tag.
sub isTag {
    my $self = shift;
    return 1 if $self->class eq 'tag';
    undef;
}

################# add a new row #############
#  Only changes local copy until you perform commit() #
#  returns true if this is a valid thing to do #
sub add (\$$$) {
  my $self = shift;
  
  my($tag,$newvalue) = rearrange([['TAG','PATH'],'VALUE'],@_);
  return undef if $self->at("$tag.$newvalue");  #already exists
  my $value;
  if (ref($newvalue)) {
    $value = $newvalue->_clone;
  } else {
    $value = $self->new('scalar',$newvalue);
  }
  my (@tags) = split('\.',$tag);
  my $p = $self;
  foreach (@tags) {
    $p = $p->_insert($_);
  }
  if ($p->{'right'}) {
    $p = $p->{'right'};
    while (1) { 
      last unless $p->{'down'};
      $p = $p->{'down'};
    }
    $p->{'down'} = $value;
  } else {
    $p->{'right'} = $value;
  }
  $newvalue =~ s/([^a-zA-Z0-9_-])/\\$1/g;
  push(@{$self->{'add'}},join(' ',@tags,$newvalue));
  delete $self->{'.PATHS'}; # uncache cached values
  1;
}

################# delete a portion of the tree #############
# Only changes local copy until you perform commit() #
#  returns true if this is a valid thing to do #
sub replace (\$$$$) {
  my $self = shift;
  my($tag,$oldvalue,$newvalue) = rearrange([['TAG','PATH'],
					    ['OLDVALUE','OLD'],
					    ['NEWVALUE','NEW']],@_);
    $self->delete($tag,$oldvalue);
    $self->add($tag,$newvalue);
    delete $self->{'.PATHS'}; # uncache cached values
    1;
}

sub commit (\$) {
    my $self = shift;
    my (@cmd);
    my $name = $self->{'name'};
    $name =~ s/([^a-zA-Z0-9_-])/\\$1/g;
    push(@cmd,"parse = $self->{'class'} $name ; " . join(' ; ',@{$self->{'add'}}))
	if defined $self->{'add'};
    push(@cmd,"parse = $self->{'class'} $name ; -D " . join(' ; -D ',@{$self->{'delete'}}))
	if defined $self->{'delete'};
    warn join("\n",@cmd),"\n" if $self->debug && @cmd;
    return undef unless my $db = $self->db;

    foreach my $cmd (@cmd) {
	my $result = $db->raw_query($cmd);
	my ($errors) = $result =~ /(\d+) errors\/\/ \d+ Active Objects/;
	if (defined($errors) and $errors > 0) {
	    $ACE::ERR = "Error during commit().  Object $self->{'name'} not correctly written.";
	    return undef;
	}
	if ($result =~ /you do not have Write Access/im) {
	  $ACE::ERR = "Write access to database denied.";
	  return undef;
	}
    }
    undef $self->{'add'};
    undef $self->{'delete'};
    return 1;
}

sub rollback (\$) {
    my $self = shift;
    undef $self->{'add'};
    undef $self->{'delete'};
    # this will force object to be reloaded from database
    # next time it is needed.
    delete $self->{'right'};
    1;
}

sub debug {
    my $self = shift;
    return defined($_[0]) ? $self->{debug}=$_[0] : $self->{debug};
}

### Get or set the date style (actually calls through to the database object) ###
sub date_style (\$;$) {
  my $self = shift;
  return undef unless $self->db;
  return $self->db->date_style(@_);
}

# return the most recent error message
sub error {
    return $ACE::ERR;
}

#####################################################################
#####################################################################
############### mostly private functions from here down #############
#####################################################################
#####################################################################
sub _clone {
    my $self = shift;
    my $pack = ref($self);
    return $pack->new($self->class,$self->name,$self->db);
}

sub _fill {
    my $self = shift;
    return if $self->filled;
    return unless $self->db && $self->isObject;
    my $data = $self->db->pick($self->class,$self->name);
    return unless $data;
    my $new = $self->newFromText($data,$self->db);
    %{$self}=%{$new};
}

# This is an incremental parser.  It replaces one level of the data structure
# with "right" and "down" pointers.
sub _parse {
  my $self = shift;
  return unless my $raw = $self->{'raw'};
  my $col = $self->{'col'};
  my $current_obj = $self;
  my $current_row = $self->{'start_row'};
  my $db = $self->{'db'};

  for (my $r=$self->{'start_row'}+1;$r<=$self->{'end_row'};$r++) {
    next unless $raw->[$r][$col];
    my $obj_on_right = $self->_fromRaw($raw,$current_row,$col+1,$r-1,$db);
    $current_obj->{'right'} = $obj_on_right;
    my $obj_down = $self->new(_ace_split($raw->[$r][$col]),$db);
    $current_obj->{'down'} = $obj_down;
    $current_obj = $obj_down;
    $current_row = $r;
  }
  $current_obj->{'right'} = $self->_fromRaw($raw,$current_row,$col+1,$self->{'end_row'},$db);
  foreach (qw/raw start_row end_row col/) {
    delete $self->{$_};
  }
}

sub _fromRaw ($$$$$;$) {
  my $pack = shift;
  $pack = ref($pack) if ref($pack);
  my ($raw,$start_row,$col,$end_row,$db) = @_;
  return undef unless $raw->[$start_row][$col];
  my ($class,$name) = _ace_split($raw->[$start_row][$col]);
  my $self = $pack->new($class,$name,$db);
  @{$self}{qw/raw start_row end_row col db/} = ($raw,$start_row,$end_row,$col,$db);
  return $self;
}


# This function, and the next, are overly long because they are optimized to prevent parsing
# parts of the tree that haven't previously been parsed.
sub _asTable (\%\$$$;) {
    my($self,$out,$position,$level) = @_;

    if ($self->{raw}) {  # we still have raw data, so we can optimize
      my ($a,$start,$end) = @{$self}{qw/col start_row end_row/};
      my @to_append = map { join("\t",@{$_}[$a..$#{$_}]) } @{$self->{'raw'}}[$start..$end];
      my $new_row;
      foreach (@to_append) {

	s/$SPLIT_PATTERN/$self->_ace_format($1,$2)/eog;
	if ($new_row++) {
	  $$out .= "\n";
	  $$out .= "\t" x ($level-1) 
	}
	$$out .= $_;
      }
      return $level-1;
    }

    $$out .= "\t" x ($level-$position-1);
    $$out .= $self->name . "\t";
    $level = $self->right->_asTable($out,$level,$level+1)
      if $self->right;
    if ($self->down) {
      $$out .= "\n";
      $level = $self->down->_asTable($out,0,$level);
    } else {
      $level--;
    }
    return $level;
}

sub _asHTML (\%\$$$;$$) {
  my($self,$out,$position,$level,$morph_code) = @_;
  $$out .= "<TR ALIGN=LEFT VALIGN=TOP>" unless $position;
  
  $$out .= "<TD></TD>" x ($level-$position-1);
  my ($cell,$prune) = $morph_code->($self);
  $$out .= "<TD>$cell</TD>";
  $level = $self->right->_asHTML($out,$level,$level+1,$morph_code) if $self->right and !$prune;
  if ($self->down) {
    $$out .= "</TR>\n";
    $level = $self->down->_asHTML($out,0,$level,$morph_code);
  } else {
    $level--;
  }
  return $level;
}

# This is the default code that will be called during construction of
# the HTML table.  It returns a two-member list consisting of the modified
# entry and (optionally) a true value if we are to prune here.  The returned string
# will be placed inside a <TD></TD> tag.  There's nothing you can do about that.
sub _default_makeHTML {
  my $self = shift;
  my ($string,$prune) = ("$self",0);
  return ($string,$prune) unless $self->isObject || $self->isTag;

  if ($self->isTag) {
    $string = "<B>$self</B>";
  } else {
    $string = qq{<FONT COLOR="blue">$self</FONT>} ;
  }
  return ($string,$prune);
}

# Return partial ace subtree at indicated tag
sub _at (\$$) {
    my ($self,$tag) = @_;
    my $pos=0;
    if ($tag=~/\[(\d+)\]$/) {
      $pos=$1;
      $tag=$`;
    }
    my $p;
    my $o = $self->right;
    while ($o) {
	return ($o->right($pos),$p,$self) if (lc($o) eq lc($tag));
	$p = $o;
	$o = $o->down;
    }
    return ();
}


# Insert a new tag or value.
# Local only. Will not affect the database.
# Returns the inserted tag, or the preexisting
# tag, if already there.
sub _insert (\$$) {
    my ($self,$tag) = @_;
    my $p = $self->{'right'};
    return $self->{'right'} = $self->new('tag',$tag)
	unless $p;
    while ($p) {
	return $p if "$p" eq $tag;
	last unless $p->{'down'};
	$p = $p->{'down'};
    }
    # if we get here, then we didn't find it, so
    # insert at the bottom
    return $p->{'down'} = $self->new('tag',$tag);
}

# This is unsatisfactory because it duplicates much of the code
# of asTable.
sub _asAce (\%\$$\@) {
  my($self,$out,$level,$tags) = @_;

  # ugly optimization for speed
  if ($self->{raw}){
    my ($a,$start,$end) = @{$self}{qw/col start_row end_row/};
    my (@last);
    foreach (@{$self->{'raw'}}[$start..$end]){
      my $j=1;
      $$out .= join("\t",@$tags) . "\t" if ($level==0) && (@$tags);
      my (@to_modify) = @{$_}[$a..$#{$_}];
      foreach (@to_modify) {
	my ($class,$name) = _ace_split($_);
	if ($name) {
	  $name = $self->_ace_format($class,$name);
	  if (_isObject($class) || $name=~/[^\w.-]/) {
	    $name=~s/"/\\"/g; #escape quotes with slashes
	    $name = qq/\"$name\"/;
	  } 
	} else {
	  $name = $last[$j] if $name eq '';
	}
	$_ = $last[$j++] = $name;  
	$$out .= "$_\t";
      }
      $$out .= "\n";
      $level = 0;
    }
    chop($$out);
    return;
  }
  
  $$out .= join("\t",@$tags) . "\t" if ($level==0) && (@$tags);
  $$out .= $self->escape . "\t";
  if ($self->right) {
    push(@$tags,$self->escape);
    $self->right->_asAce($out,$level+1,$tags);
    pop(@$tags);
  }
  if ($self->down) {
    $$out .= "\n";
    $self->down->_asAce($out,0,$tags);
  }
}

sub _to_ace_date {
  my $self = shift;
  my $string = shift;
  return $string unless lc($self->date_style) eq 'ace';
  %MO = (Jan=>1,Feb=>2,Mar=>3,
	 Apr=>4,May=>5,Jun=>6,
	 Jul=>7,Aug=>8,Sep=>9,
	 Oct=>10,Nov=>11,Dec=>12) unless %MO;
  my ($day,$mo,$yr) = split(" ",$string);
  return "$yr-$MO{$mo}-$day";
}

# split a -j string into class and name types
sub _ace_split {
  return $_[0]=~/^${SPLIT_PATTERN}$/o;
}

# Used to munge special data types.  Right now dates are the
# only examples.
sub _ace_format {
  my $self = shift;
  my ($class,$name) = @_;
  return $class eq 'date' ? $self->_to_ace_date($name) : $name;
}

# It's an object unless it is one of these things
sub _isObject {
  $_[0] !~ /^(float|int|date|tag|txt|peptide|dna|scalar|[Tt]ext|comment)$/;
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;

__END__

=head1 NAME

Ace - open an ACE database server for reading and writing

=head1 SYNOPSIS

    # open database connection(s)
    use Ace;
    $db = Ace->connect(-host => 'sapiens.wustl.edu',
                       -port => 2000525);
    @sequences = $db->list('Sequence','D*');
    $sequence = $db->fetch('Sequence,'D12345');
    $number = $db->count('Sequence','D*');
    @sequences = $db->fetch('Sequence','D*');
    $i = $db->fetch_many(Sequence,'*');  # fetch a cursor
    while ($obj = $i->next) {
       print $obj->asTable;
    }

    
    # Inspect the object
    $r    = $sequence->at('Visible.Overlap_Right');
    @row  = $sequence->row;
    @col  = $sequence->col;
    @tags = $sequence->tags;
    
    # Explore object substructure
    @more_tags = $sequence->at('Visible')->tags;
    @col       = $sequence->at("Visible.$more_tags[1]")->col;

    # Follow a pointer into database
    $r     = $sequence->at('Visible.Overlap_Right')->fetch;
    $next  = $r->at('Visible.Overlap_left')->fetch;

    # Pretty-print object
    print $sequence->asString;
    print $sequence->asTabs;
    print $sequence->asHTML;

    # Update object
    $sequence->replace('Visible.Overlap_Right',$r,'M55555');
    $sequence->add('Visible.Homology','GR91198');
    $sequence->delete('Source.Clone','MBR122');
    $r->commit();

    # Rollback changes
    $r->rollback()

    # Get errors
    print Ace->error;
    print $sequence->error;

=head1 DESCRIPTION

This module provides an interface to the ACEDB object-oriented
database.  Both read and write access is provided, and ACE objects are
returned as similarly-structured Perl objects.  Multiple databases can
be opened simultaneously.

You will interact with two Perl classes: Ace, and Ace::Object.  Ace is
the database, and Ace::Object is the superclass for all objects
returned from the database.  The two classes are linked: if you
retrieve an Ace::Object from a particular database, it will store a
reference to the database and use it to fetch any subobjects contained
within it.  You may make changes to the Ace::Object and have those
changes written into the database.  You may also create Ace::Objects
from scratch, and store them in the database.

=head1 CREATING NEW DATABASE CONNECTIONS: connect()

    # remote database
    $db = Ace->connect(-host  =>  'sapiens.wustl.edu',
                       -port  =>  123456);
    
    # local (non-server) database
    $db = Ace->connect(-path  =>  '/usr/local/acedb);

Use Ace::connect() to establish a connection to a networked or local
AceDB database.  To establish a connection to an AceDB server, use the
B<-host> and/or B<-port> arguments.  For a local server, use the
B<-port> argument.  The database must be up and running on the
indicated host and port prior to connecting to an AceDB server.  The
full syntax is as follows:

    $db = Ace->connect(-host  =>  $host,
                       -port  =>  $port,
		       -path  =>  $database_path,
		       -program =>$local_connection_program
                       -class =>  $object_class);

The connect() method uses a named argument calling style, and
recognizes the arguments B<-host>, B<-port>, B<-path>, B<-program> and
B<-class>.  

=over 4

=item B<-host>, B<-port>

These arguments point to the host and port of an AceDB server.
AcePerl will use its internal compiled code to establish a connection
to the server unless explicitly overridden with the B<-program>
argument.

=item B<-path>

This argument indicates the path of an AceDB directory on the local
system.  It should point to the directory that contains the I<wspec>
subdirectory.  User name interpolations (~acedb) are OK.

=item B<-program>

By default AcePerl will use its internal compiled code calls to
establish a connection to Ace servers, and will launch a I<tace>
subprocess to communicate with local Ace databases.  The B<-program>
argument allows you to customize this behavior by forcing AcePerl to
use a local program to communicate with the database.  This argument
should point to an executable on your system.  You may use either a
complete path or a bare command name, in which case the PATH
environment variable will be consulted.  For example, you could force
AcePerl to use the I<aceclient> program to connect to the remote host
by connecting this way:

  $db = Ace->connect(-host=>'sapiens.wustl.edu',-port=>123456,
                     -program=>'aceclient');

=item B<-class>

The optional B<-class> argument points to the class you would like to
return from database queries.  It is provided for your use if you
subclass Ace::Object.  For example, if you have created a subclass of
Ace::Object called Ace::Object::Graphics, you can have the database
return this subclass by default by connecting this way:

  $db = Ace->connect(-host=>'sapiens.wustl.edu',-port=>123456,
	             -class=>'Ace::Object::Graphics');

=back

If arguments are omitted, they will default to the following values:

    -host         localhost
    -port         23456
    -path         <no default>
    -program      tace
    -class        Ace::Object

If you prefer to use a more Smalltalk-like message-passing syntax, you
can open a connection this way too:

    $db = connect Ace -host=>'sapiens',-port=>123456;

The return value is an Ace handle to use to access the database, or
undef if the connection fails.  If the connection fails, an error
message can be retrieved by calling Ace->error.

You may check the status of a connection at any time with ping().  It
will return a true value if the database is still connected.  Note
that Ace will timeout clients that have been inactive for any length
of time.  Long-running clients should attempt to reestablish their 
connection if ping() returns false.

    $db->ping() || die "not connected";

You may perform low-level calls using the Ace client C API by calling
db().  This fetches an Ace::AceDB object.  See THE LOW LEVEL C API for
details on using this object.
 
    $low_level = $db->db();

=head1 RETRIEVING ACEDB OBJECTS

Once you have established a connection and have an Ace databaes
handle, several methods can be used to query the ACE database to
retrieve certain objects.

=head2 list() method

    @objects = $db->list(class,pattern,[count,offset]);
    @objects = $db->list(-class=>$class,
                         -name=>$name_pattern,
                         -count=>$count,
                         -offset=>$offset);

This function queries the database for a list of objects matching the
specified class and pattern, returning a list of Ace::Objects.  The
class may be any class name recogized by the database's model.  The
pattern may be a full object identifier, or may contain wildcard
characters (* and ?).  For example, you can retrieve all Sequence
objects with this request:

    @sequences = $db->list('Sequence','*');

You may limit the number of objects to be listed by providing optional
offset and count parameters.  For example, this fetches 100 sequences
starting at the 500th.

    @some_sequences = $db->list('Sequence','*',100,500);

=head2 count() method

    $count = $db->list(class,pattern);

This function queries the database for a list of objects matching the
specified class and pattern, and returns the object count.  For large
sets of objects this is much more time and memory effective than
fetching the entire list.

The class and name pattern are the same as the list() method above.

=head2 fetch() method

    $object = $db->fetch($class,$name_pattern);
    @objects = $db->fetch($class,$name_pattern);
    @objects = $db->fetch(-name=>$name_pattern,
                          -class=>$class
			  -count=>$count,
			  -offset=>$offset,
                          -fill=>$fill);

Ace::fetch() is similar to Ace::list(), but retrieves whole objects,
rather than a list.  It will either return a list of Ace::Objects, or
an empty list (or undef) in the case of an error.  Errors may occur
when the indicated object is not found in the database, if the
provided name contains wildcard characters, or if an error occurs
during communications.  A string describing the error can be found in
Ace->error.  For example, the first line of code will fetch the
Sequence object whose database ID is I<D12345>.  The second line
will retrieve all objects matching the pattern I<D1234*>.

   $object = $db->fetch(Sequence,'D12345');
   @objects = $db->fetch(Sequence,'D1234*');

When you know you need to retrieve and manipulate multiple objects, it
is faster to call fetch() with a pattern than to call list() and
manipulate the objects individually.  This is because list() returns
just the B<name> of the object, which is then filled in when needed.
Fetch() returns the B<entire> filled-in object.  There is latency
overhead every time you go back to the database.

In the named parameter calling form, B<-count> can be used to retrieve
a certain maximum number of objects starting at offset B<-offset>.
The B<-fill> parameter (also known by its pseudonym B<-filled>) allows
you to control when Ace.pm will "fill" the object.  Ordinarily, Ace.pm
defers fetching the whole object from the remote server, only filling
in fields at the time you request them.  This is a good heuristic for
conserving memory, but gives lousy performance when network latency is
high, or when you know you will be reading fields from all the
objects.  B<-fill>, if passed a true value, will get all the
information from the server at once, improving performance, and
dramatically increasing the amount of memory your program needs to
hold the objects.  Consider using B<fetch_many()> instead.

=head2 find() method

    @objects = $db->query($query_string);
    @objects = $db->query(-query=>$query_string,
                          -offset=>$offset,
                          -count=>$count
                          -fill=>$fill);

This allows you to pass arbitrary Ace query strings to the server and
retrieve all objects that are returned as a result.  For example, this
code fragment retrieves all papers written by author "Meyer BF":

    @papers = $db->query('author IS "Meyer BF" ; >Paper');

The full query syntax is described in
http://where.the.hell.is.that.bloody.doc/

In the named parameter calling form, B<-count>, B<-offset>, and
B<-fill> have the same meanings as in B<fetch()>.

=head2 fetch_many() method

    $obj = $db->fetch_many($class,$pattern);
    $obj = $db->fetch_many(-class=>$class,
                           -name=>$pattern);

If you expect to retrieve many objects, you can fetch an iterator
across the data set.  This is friendly both in terms of network
bandwidth and memory consumption.  It is simple to use:

    $i = $db->fetch_many(Sequence,'*');  # all sequences!!!!
    while ($obj = $i->next) {
       print $obj->asTable;
    }

The iterator will return undef when it has finished iterating, and
cannot be used again.

=head2 new() method

   $obj = $db->new($class,$name);
   $obj = $db->new(-class=>$class,
                   -name=>$name);

Create a new object in the database with the indicated class and name
and return a pointer to it.  Will return undef if the object already
exists in the database.  The object isn't actually written into the database
until you call Ace::Object::commit().

=head2 raw_query() method

    $r = $db->raw_query('Model');

Send a command to the database and return its unprocessed output.
This method is necessary to gain access to features that are not yet
implemented in this module, such as model browsing and complex
queries.

=head2 classes() method

   @classes = $db->classes();
   @all_classes = $db->classes(1);

This method returns a list of all the object classes known to the
server.  In a list context it returns an array of class names.  In a
scalar context, it the number of classes defined in the database.

Ordinarily I<classes()> will return only those classes that are
exposed to the user interface for browsing, the so-called "visible"
classes.  Pass a true argument to the call to retrieve non-visible
classes as well.

=head2 date_style() method
 
  $style = $db->date_style();
  $style = $db->date_style('ace');
  $style = $db->date_style('java');

For historical reasons, AceDB can display dates using either of two
different formats.  The first format, which I call "ace" style, puts
the year first, as in "1997-10-01".  The second format, which I call
"java" style, puts the day first, as in "01 Oct 1997 00:00:00" (this
is also the style recommended for Internet dates).  The default is to
use the latter notation.

B<date_style()> can be used to set or retrieve the current style.
Called with no arguments, it returns the current style, which will be
one of "ace" or "java."  Called with an argument, it will set the
style to one or the other.

=head2 error() method

    Ace->error;

This returns the last error message.  Like UNIX errno, this variable
is not reset between calls, so its contents are only valid after a
method call has returned a result value indicating a failure.

For your convenience, you can call error() in any of several ways:

    print Ace->error();
    print $db->error();  # $db is an Ace database handle
    print $obj->error(); # $object is an Ace::Object

=head1 MANIPULATING ACEDB OBJECTS

Objects returned from Ace databases are of type Ace::Object.
Currently there is only one type of Ace::Object, but this may change
in the future to support more interesting object-specific behaviors.

The structure of an Ace::Object is very similar to that of an Acedb
object.  It is a tree structure like this one (an Author object):

Thierry-Mieg J->Full_name ->Jean Thierry-Mieg
                 |
                Laboratory->FF
                 |
                Address->Mail->CRBM duCNRS
                 |        |     |
                 |        |    BP 5051
                 |        |     |
                 |        |    34033 Montpellier
                 |        |     |
                 |        |    FRANCE
                 |        |
                 |       E_mail->mieg@kaa.cnrs-mop.fr
                 |        |
                 |       Phone ->33-67-613324
                 |        |
                 |       Fax   ->33-67-521559
                 |
                Paper->The C. elegans sequencing project
                        |
                       Genome Project Database
                        |
                       Genome Sequencing
                        |
                       How to get ACEDB for your Sun
                        |
                       ACEDB is Hungry


Each object in the tree has two pointers, a "right" pointer to the
node on its right, and a "down" pointer to the node beneath it.  Right
pointers are used to store hierarchical relationships, such as
Address->Mail->E_mail, while down pointers are used to store lists,
such as the multiple papers written by the Author.

Each node in the tree has a type and a name.  Types include integers,
strings, text, floating point numbers, as well as specialized
biological types, such as "dna" and "peptide."  Another fundamental
type is "tag," which is a text identifier used to label portions of
the tree.  Examples of tags include "Paper" and "Laboratory" in the
example above.

In addition to these built-in types, there are constructed types known
as classes.  These types are specified by the data model.  In the
above example, "Thierry-Mieg J" is an object of the "Author" class,
and "Genome Project Database" is an object of the "Paper" class.  An
interesting feature of objects is that you can follow them into the
database, retrieving further information.  For example, after
retrieving the "Genome Project Database" Paper from the Author object,
you could fetch more information about it, either by following B<its>
right pointer, or by using one of the specialized navigation routines
described below.

=head2 new() method

    $object = new Ace::Object($class,$name,$database);
    $object = new Ace::Object(-class=>$class,
                              -name=>$name,
                              -db=>database);

You can create a new Ace::Object from scratch by calling the new()
routine with the object's class, its identifier and a handle to the
database to create it in.  The object won't actually be created in the
database until you commit() it (see below).  If you do not provide a
database handle, the object will be created in memory only.

Arguments can be passed positionally, or as named parameters, as shown
above.

This routine is usually used internally.  See also add(), delete() and
replace() for ways to manipulate this object.

=head2 name() method

    $name = $object->name();

Return the name of the Ace::Object.  This happens automatically
whenever you use the object in a context that requires a string or a
number.  For example:

    $object = $db->fetch(Author,"Thierry-Mieg J");
    print "$object did not write 'Pride and Prejudice.'\n";

=head2 class() method

    $class = $object->class();

Return the class of the object.  The return value may be one of
"float," "int," "date," "tag," "txt," "dna," "peptide," and "scalar."
(The last is used internally by Perl to represent objects created
programatically prior to committing them to the database.)  The class
may also be a user-constructed type such as Sequence, Clone or
Author.  These user-constructed types usually have an initial capital
letter.

=head2 db() method

     $db = $object->db();

Return the database that the object is associated with.

=head2 isClass() method

     $bool = $object->isClass();

Returns true if the object is a class (can be fetched from the
database).

=head2 isTag() method

     $bool = $object->isTag();

Returns true if the object is a tag.

=head2 tags() method

     @tags = $object->tags();

Return all the top-level tags in the object as a list.  In the Author
example above, the returned list would be
('Full_name','Laboratory','Address','Paper').  

You can fetch tags more deeply nested in the structure by navigating
inwards using the methods listed below.

=head2 right() and down() methods

     $subtree = $object->right;
     $subtree = $object->right($position);	
     $subtree = $object->down;
     $subtree = $object->down($position);	

B<right()> and B<down()> provide a low-level way of traversing the
tree structure by following the tree's right and down pointers.
Called without any arguments, these two methods will move one step.
Called with a numeric argument >= 0 they will move the indicated
number of steps (zero indicates no movement).

     $full_name = $object->right->right;
     $full_name = $object->right(2);

     $city = $object->right->down->down->right->right->down->down;
     $city = $object->right->down(2)->right(2)->down(2);

If $object contains the "Thierry-Mieg J" Author object, then the first
series of accesses shown above retrieves the string "Jean
Thierry-Mieg" and the second retrieves "34033 Montpellier."  If the
right or bottom pointers are NULL, these methods will return undef.

In addition to being somewhat awkard, you will probably never need to
use these methods.  A simpler way to retrieve the same information
would be to use the at() method described in the next section.  

The right() and down() methods always walk through the tree of the
current object.  They do not follow object pointers into the database.
Use B<fetch()> (or the deprecated B<pick()> or B<follow()> methods)
instead.

=head2 at() method

    $subtree    = $object->at($tag_path);
    @values     = $object->at($tag_path);

at() is a simple way to fetch the portion of the tree that you are
interested in.  It takes a single argument, a simple tag or a path.  A
simple tag, such as "Full_name", must correspond to a tag in the
column immediately to the right of the root of the tree.  A path such
as "Address.Mail" is a dot-delimited path to the subtree.  Some
examples are given below.

    ($full_name)   = $object->at('Full_name');
    @address_lines = $object->at('Address.Mail');

The second line above is equivalent to:

    @address = $object->at('Address')->at('Mail');

Called without a tag name, at() just dereferences the object,
returning whatever is to the right of it, the same as
$object->{'right'}.

If a path component already has a dot in it, you may escape the dot
with a backslash, as in:

    $s=$db->fetch('Sequence','M4');
    @homologies = $s->at('Homol.DNA_homol.yk192f7\.3';

This also demonstrates that path components don't necessarily have to
be tags, although in practice they usually are.

at() returns slightly different results depending on the context in
which it is called.  In a list context, it returns the column of
values to the B<right> of the tag.  However, in a scalar context, it
returns the subtree rooted at the tag.  To appreciate the difference,
consider these two cases:

    $name1   = $object->at('Full_name');
    ($name2) = $object->at('Full_name');

After these two statements run, $name1 will be the tag object named
"Full_name", and $name2 will be the text object "Jean Thierry-Mieg",
The relationship between the two is that $name1->right leads to
$name2.  This is a powerful and useful construct, but it can be a trap
for the unwary.  If this behavior drives you crazy, use this
construct:
  
    $name1   = $object->at('Full_name')->at();

For finer control over navigation, path components can include
optional indexes to indicate navigation to the right of the current
path component.  Here is the syntax:

    $object->at('tag1[index1].tag2[index2].tag3[index3]...');

Indexes are zero-based.  An index of [0] indicates no movement
relative to the current component, and is the same as not using an
index at all.  An index of [1] navigates one step to the right, [2]
moves two steps to the right, and so on.  Using the Thierry-Mieg
object as an example again, here are the results of various indexes:

    $object = $db->fetch(Author,"Thierry-Mieg J");
    $a = $object->at('Address[0]')   --> "Address"
    $a = $object->at('Address[1]')   --> "Mail"
    $a = $object->at('Address[2]')   --> "CRBM duCNRS"

In an array context, the last index in the path does something very
interesting.  It returns the entire column of data K steps to the
right of the path, where K is the index.  This is used to implement
so-called "tag[2]" syntax, and is very useful in some circumstances.
For example, here is a fragment of code to return the Thierry-Mieg
object's full address without having to refer to each of the
intervening "Mail", "E_Mail" and "Phone" tags explicitly.

   @address = $object->at('Address[2]');
   --> ('CRBM duCNRS','BP 5051','34033 Montpellier','FRANCE',
        'mieg@kaa.cnrs-mop.fr,'33-67-613324','33-67-521559')

Similarly, "tag[3]" will return the column of data three hops to the
right of the tag.  "tag[1]" is identical to "tag" (with no index), and
will return the column of data to the immediate right.  There is no
special behavior associated with using "tag[0]" in an array context;
it will always return the subtree rooted at the indicated tag.

Internal indices such as "Homol[2].BLASTN", do not have special
behavior in an array context.  They are always treated as if they were
called in a scalar context.

Also see B<col()> and B<search()>.

=head2 search() method

    $subtree    = $object->search($tag);
    @values     = $object->search($tag);
    @values     = $object->search($tag,$position);

The search() method will perform a breadth-first search through the
object (columns first, followed by rows) for the tag indicated by the
argument, returning the column of the portion of the subtree it points
to.  For example, this code fragment will return the value of the
"Fax" tag.

    ($fax_no) = $object->search('Fax');
         --> "33-67-521559"

The list versus scalar context semantics are the same as in at(), so
if you want to retrieve the scalar value pointed to by the indicated
tag, either use a list context as shown in the example, above, or a
dereference, as in:

     $fax_no = $object->search('Fax');
         --> "Fax"
     $fax_no = $object->search('Fax')->at;
         --> "33-67-521559"

An optional second argument to B<search()>, $position, allows you to
navigate the tree relative to the retrieved subtree.  Like the B<at()>
navigational indexes, $position must be a number greater than or equal
to zero.  In a scalar context, $position moves rightward through the
tree.  In an array context, $position implements "tag[2]" semantics.

For example:

     $fax_no = $object->search('Fax',0);
          --> "Fax"

     $fax_no = $object->search('Fax',1);
          --> "33-67-521559"

     $fax_no = $object->search('Fax',2);
          --> undef  # nothing beyond the fax number

     @address = $object->search('Address',2);
          --> ('CRBM duCNRS','BP 5051','34033 Montpellier','FRANCE',
               'mieg@kaa.cnrs-mop.fr,'33-67-613324','33-67-521559')

=head2 Autogenerated Access Methods

     $scalar = $object->Name_of_tag;
     $scalar = $object->Name_of_tag($position);
     @array  = $object->Name_of_tag;
     @array  = $object->Name_of_tag($position);

The module attempts to autogenerate data access methods as needed.
For example, if you refer to a method named "Fax" (which doesn't
correspond to any of the built-in methods), then the code will call
the B<search()> method to find a tag named "Fax" and return its
contents.  The list and scalar context semantics are the same as in
B<search()>.  

You can provide an optional positional index to rapidly navigate
through the tree or to obtain tag[2] behavior.  In the following
examples, the first two return the object's Fax number, and the third
returns all data two hops to the right of Address.

     ($fax_no) = $object->Fax;
     $fax_no   = $object->Fax(1);
     @address  = $object->Address(2);

If no matching tag is found, the autogenerated method will return
undef or an empty array.

=head2 fetch() method

    $new_object = $object->fetch;
    $new_object = $object->fetch($tag);

Follow object into the database, returning a new object.  This is
the best way to follow object references.  For example:

    $laboratory = $object->at('Laboratory')->fetch;
    print $laboratory->asString;

Because the previous example is a frequent idiom, the optional $tag
argument allows you to combine the two operations into a single one:

    $laboratory = $object->fetch('Laboratory');

=head2 pick() method

Deprecated method.  This has the same semantics as fetch(), which
should be used instead.

=head2 follow() method

Deprecated method.  This has the same semantics as fetch(), which
should be used instead.

=head2 col() method

     @column = $object->col;
     @column = $object->col($position);


B<col()> flattens a portion of the tree by returning the column one
hop to the right of the current subtree. You can provide an additional
positional index to navigate through the tree using "tag[2]" behavior.
This example returns the author's mailing address:

  @mailing_address = $object->at('Address.Mail')->col();

This example returns the author's entire address including mail,
e-mail and phone:

  @address = $object->at('Address')->col(2);

It is equivalent to any of these calls:

  $object->at('Address[2]');
  $object->search('Address',2);
  $object->Address(2);

Use whatever syntax is most comfortable for you.

=head2 row() method

     @row=$object->row();
     @row=$object->row($position);

B<row()> will return the row of data to the right of the object.  The
first member of the list will be the object itself.  In the case of
the "Thierry-Mieg J" object, the example below will return the list
('Address','Mail','CRBM duCNRS').

     @row = $object->Address->row();

You can provide an optional position to move rightward one or more
places before retrieving the row.  This code fragment will return
('Mail','CRBM duCNRS'):

     @row = $object->Address->row(1);

It is exactly equivalent to:

     @row = $object->Address->right->row();

=head2 asString() method

    $object->asString;

asString() returns a pretty-printed ASCII representation of the object
tree.

=head2 asTable() method

    $object->asTable;

asTable() returns the object as a tab-delimited text table.

=head2 asAce() method

    $object->asAce;

asAce() returns the object as a tab-delimited text table with B<all>
the intermediate tags filled in.  It is something like an Ace dump,
but not really, because the table cells aren't escaped for proper ACE
parsing, so it can't be fed back into ACE.  Sean Walsh
(wsean@nasc.nott.ac.uk) thought this would be a "handy feature," and
I've implemented it.  Suggestions are welcome.

=head2 asHTML() method

   $object->asHTML;
   $object->asHTML(\&tree_traversal_code);

asHTML() returns an HTML 3 table representing the object, suitable for
incorporation into a Web browser page.  The callback routine, if
provided, will have a chance to modify the object representation
before it is incorporated into the table, for example by turning it
into an HREF link.  The callback takes a single argument containing
the object, and must return a string-valued result.  It may also
return a list as its result, in which case the first member of the
list is the string representation of the object, and the second
member is a boolean indicating whether to prune the table at this
level.  For example, you can prune large repetitive lists.

Here's a complete example:

   sub process_cell {
     my $obj = shift;
     return "$obj" unless $obj->isObject || $obj->isTag;

     my @col = $obj->col;
     my $cnt = scalar(@col);
     return ("$obj -- $cnt members",1);  # prune
            if $cnt > 10                 # if subtree to big

     # tags are bold
     return "<B>$obj</B>" if $obj->isTag;  

     # objects are blue
     return qq{<FONT COLOR="blue">$obj</FONT>} if $obj->isObject; 
   }

   $object->asHTML(\&process_cell);


=head2 add() method

    $result_code = $object->add($tag,$value);    
    $result_code = $object->add(-path=>$tag,
				-value=>$value);    

add() updates the tree by adding data to the indicated tag path.  The
example given below adds the value "555-1212" to a new Address entry
named "Pager".  You may call add() a second time to add a new value
under this tag, creating multi-valued entries.

    $object->add('Address.Pager','555-1212');

No check is done against the database model for the correct data type
or tag path.  The update isn't actually performed until you call
commit(), at which time a result code indicates whether the database
update was successful.

You may create objects that reference other objects this way:

    $lab = new Ace::Object('Laboratory','LM',$db);
    $lab->add('Full_name','The Laboratory of Medicine');
    $lab->add('City','Cincinatti');
    $lab->add('Country','USA');

    $author = new Ace::Object('Author','Smith J',$db);
    $author->add('Full_name','Joseph M. Smith');
    $author->add('Laboratory',$lab);

    $lab->commit();
    $author->commit();

The result code indicates whether the addition was syntactically
correct.  Currently it is always true, since the database model is not
checked.

=head2 delete() method

    $result_code = $object->delete($tag_path,$value);
    $result_code = $object->delete(-path=>$tag_path,
                                   -value=>$value);

Delete the indicated tag and value from the object.  This example
deletes the address line "FRANCE" from the Author's mailing address:

    $object->delete('Address.Mail','FRANCE');

No actual database deletion occurs until you call commit().  The
delete() result code indicates whether the deletion was successful.
Currently it is always true, since the database model is not checked.
    
=head2 replace() method

    $result_code = $object->replace($tag_path,$oldvalue,$newvalue);
    $result_code = $object->replace(-path=>$tag_path,
				    -old=>$oldvalue,
				    -new=>$newvalue);

Replaces the indicated tag and value with the new value.  This example
changes the address line "FRANCE" to "LANGUEDOC" in the Author's
mailing address:

    $object->delete('Address.Mail','FRANCE','LANGUEDOC');

No actual database changes occur until you call commit().  The
delete() result code indicates whether the replace was successful.
Currently is true if the old value was identified.

=head2 commit() method

     $result_code = $object->commit;

Commits all add(), replace() and delete() operations to the database.
It can also be used to write a completely new object into the
database.  The result code indicates whether the object was
successfully written.  If an error occurred, further details can be
found in the Ace->error() error string.

=head2 rollback() method

    $object->rollback;

Discard all adds, deletions and replacements, returning the object to
the state it was in prior to the last commit().

rollback() works by deleting the object from Perl memory and fetching
the object anew from AceDB.  If someone has changed the object in the
database while you were working with it, you will see this version,
ot the one you originally fetched.

=head2 date_style() method

   $object->date_style('ace');

This is a convenience method that can be used to set the date format
for all objects returned by the database.  It is exactly equivalent to

   $object->db->date_style('ace');

Note that the text representation of the date will change for all
objects returned from this database, not just the current one.

=head2 error() method
    
    $object->error;

Returns the error from the previous operation, if any.  As in
Ace::error(), this string will only have meaning if the previous
operation returned a result code indicating an error.

=head2 debug() method

    $object->debug(1);

Change the debugging mode.  A zero turns of debugging messages.
Integer values produce debug messages on standard error.  Higher
integers produce progressively more verbose messages.

=head1 THE LOW LEVEL C API

Internally Ace.pm makes C-language calls to libace to send query
strings to the server and to retrieve the results.  The class that
exports the low-level calls is named Ace::AceDB.

The following methods are available in Ace::AceDB:

=over 4

=item new($host,$port,$timeout)

Connect to the host $host at port $port. Timeout after $timeout
seconds.  If timeout is not specified, it defaults to 25.

If successful, this call returns an Ace::AceDB connection object.
Otherwise, it returns undef.  Example:

  $acedb = Ace::AceDB->new('localhost',200005,5) 
           || die "Couldn't connect";

The Ace::AceDB object can also be accessed from the high-level Ace
interface by calling the ACE::db() method:

  $db = Ace->new(-host=>'localhost',-port=>200005);
  $acedb = $db->db();

=item query($request)

Send the query string $request to the server and return a true value
if successful.  You must then call read() repeatedly in order to fetch
the query result.

=item read()

Read the result from the last query sent to the server and return it
as a string.  ACE may return the result in pieces, breaking between
whole objects.  You may need to read repeatedly in order to fetch the
entire result.  Canonical example:

  $acedb->query("find Sequence D*");
  die "Got an error ",$acedb->error() if $acedb->status == STATUS_ERROR;
  while ($acedb->status == STATUS_PENDING) {
     $result .= $acedb->read;
  }

=item status()

Return the status code from the last operation.  Status codes are
exported by default when you B<use> Ace.pm.  The status codes you may
see are:

  STATUS_WAITING    The server is waiting for a query.
  STATUS_PENDING    A query has been sent and Ace is waiting for
                    you to read() the result.
  STATUS_ERROR      A communications or syntax error has occurred

=item error()

Returns a more detailed error code supplied by the Ace server.  Check
this value when STATUS_ERROR has been returned.  These constants are
also exported by default.  Possible values:

 ACE_INVALID           
 ACE_OUTOFCONTEXT
 ACE_SYNTAXERROR
 ACE_UNRECOGNIZED

Please see the ace client library documentation for a full description
of these error codes and their significance.

=item encore()

This method may return true after you have performed one or more
read() operations, and indicates that there is more data to read.  You
will not ordinarily have to call this method.

=back

=head1 BUGS

1. The ACE model should be consulted prior to updating the database.

2. There is no automatic recovery from connection errors.

3. Debugging has only one level of verbosity, despite the best
of intentions.

4. Performance is poor when fetching big objects, because of 
many object references that must be created.  This could be
improved.

5. When called in an array context at("tag[0]") should return the
current tag's entire column.  It returns the current subtree instead.

6. Item number six is missing.

=head1 SEE ALSO

Jade documentation

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1997-1998, Lincoln D. Stein

This library is free software; 
you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut

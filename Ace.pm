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
$VERSION = '1.21';

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
    my ($host,$port) = rearrange([qw/HOST PORT/],@_);
    $host ||= 'localhost';
    $port ||= 200001;

    # open up a connection to the database
    my $database = Ace::AceDB->new($host,$port);
    unless ($database) {
	$ACE::ERR = "Couldn't open database";
	return undef;
    }


    my $self = bless {
	'database'=> $database,
	'host'   => $host,
	'port'   => $port,
    },$class;

    return $self;
}

# return true if the database is still connected
sub ping {
  my $self = shift;
  local($SIG{PIPE})='IGNORE';  # so we don't get a fatal exception during the check
  $self->raw_query('') || return undef;
  return !$self->{database}->status;
}

sub fetch {
    my ($self,$class,$pattern) = @_;
    my ($start,$count) = (0,-1);
    $count = 1 unless wantarray;
    $self->query("find $class $pattern");
    my (@h) = $self->_list($start,$count);
    return $h[0]
}

sub fetch_many {
  my ($self,$class,$pattern) = @_;
  my $iterator = Ace::Iterator->new($self,"find $class $pattern");
  $self->_register_iterator($iterator);
  return $iterator;
}

sub list {
    my ($self,$class,$pattern) = @_;
    my @result;
    $self->raw_query("find $class $pattern");
    $self->_list;
}

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
    my ($self,$class,$pattern) = @_;
    undef $ERR;
    return () unless $self->count($class,$pattern);
    
    # if we get here, then we've got some data to return.
    my @result;
    my $result = $self->raw_query("show -j");
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

# do a query, but don't return the result
sub query {
  my ($self,$query) = @_;
  $self->_alert_iterators;
  $self->{'database'}->query($query);
}

# do a query, and return the result immediately
sub raw_query {
    my ($self,$query) = @_;
    $self->{database}->query($query);
    $self->_alert_iterators;
    return $self->read_object;
}

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

# return a portion of the active list
sub _list {
  my $self = shift;
  my ($start,$count) = @_;
  ($start,$count) = (0,-1) unless $count;
  my (@result);
  my $result = $self->raw_query("list -j -b $start -c $count");
  while ($result =~ /^\?(\w+)\?(.+)\?/mg) {
    push(@result,Ace::Object->new($1,$2,$self));
  }
  return @result;
}

# return a portion of the active list
sub _fetch {
  my $self = shift;
  my ($start,$count) = @_;
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
    push(@result,Ace::Object->newFromText($_,$self));
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
    $self->{'db'}->query($self->{'query'});
    $self->{'db'}->query("show -j -b $self->{'current'} -c -1");
    $self->{'valid'}++;
  }
  my @objects = $self->{'db'}->_fetch_chunk;
  $self->{'cached_answers'} = \@objects;
}

##########################################################################
##########################################################################
package Ace::Object;

use overload 
    '""'       => 'name',
    'fallback' =>' TRUE';
use vars '$AUTOLOAD';

# I get confused by this
*isClass = \&isObject;
*rearrange = \&Ace::rearrange;

sub AUTOLOAD {
    my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    my $self = shift;
    if ($func_name =~/__/) {
      $func_name =~ s/__/./g;
      return $self->at($func_name);
    }
    return $self->search($func_name);
}

sub DESTROY { }

###################### object constructor #################
sub new ($$$;\$) {
    my($pack,$class,$name,$db) = @_;
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
  my @array;
  foreach (split("\n",$text)) {
    next unless $_;
    push(@array,[split("\t")]);
  }
  return $pack->_fromRaw(\@array,0,0,$#array,$db);
}


################### name of the object #################
sub name (\$) {
    my $self = shift;
    defined($_[0])
	? $self->{name} = shift
	: $self->{name};
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
    my ($self,$tag,$return_parent) = @_;
    return $self->{'right'} unless $tag;

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
    return $o->col if wantarray;
    return $o;
}

### Flatten out part of the tree into an array ####
### along the row.  Will not follow object references.  ###
sub row (\$) {
  my $self = shift;
  my @r;
  my $o = $self->right;
  while ($o) {
    push(@r,$o);
    $o = $o->right;
  }
  return wantarray ? @r : $r[0];
}

### Flatten out part of the tree into an array ####
### along the column. Will not follow object references. ###
sub col (\$) {
    my $self = shift;
    my @r;
    my $o = $self->right;
    while ($o) {
	push(@r,$o);
	$o = $o->down;
    }
    return wantarray ? @r : $r[0];
}

#### Search for a tag, and return the column ####
#### Uses a breadth-first search (cols then rows) ####
sub search (\$$;$) {
    my ($self,$tag) = @_;

    TRY: {
	last TRY if exists $self->{'.PATHS'}->{$tag};
	
	my @col = $self->col;
	foreach (@col) {
	  if ($_ eq $tag) {
	    $self->{'.PATHS'}->{$tag} = $_;
	    last TRY;
	  }
	}

	# if we get here, we didn't find it in the column,
	# so we call ourselves recursively to find it
	foreach (@col) {
	  if (my $r = $_->search($tag)) {
	    $self->{'.PATHS'}->{$tag} = $r;	
	    last TRY;
	  }
	}

	# If we got here, we didn't find it.  So tag the cache
	# as empty.
	$self->{'.PATHS'}->{$tag} = undef;
      }

    return wantarray ? $self->{'.PATHS'}->{$tag}->col
                     : $self->{'.PATHS'}->{$tag} 
           if $self->{'.PATHS'}->{$tag};
    return wantarray ? () : undef;
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

### Return the pretty-printed HTML table representation ###
### may pass a code reference to add additional formatting to cells ###
sub asHTML (\$;$) {
    my $self = shift;
    my $modify_code = shift;
    my $string = "<TABLE BORDER>\n<TR ALIGN=LEFT><TH>$self</TH>";
    $self->right->_asHTML(\$string,1,2,$modify_code);
    $string .= "</TR>\n</TABLE>";
    return $string;
}


#### As tab-delimited table ####
sub asTable (\$) {
    my $self = shift;
    my $string = "$self\t";
    $self->right->_asTable(\$string,1,2);
    return $string . "\n";
}

### Pretty-printed version -- this should use a FORMAT statement ###
sub asString {
  my $self = shift;
  my $tabs = $self->asTable;
  my(@lines) = split("\n",$tabs);
  my($result,@max);
  foreach (@lines) {
    my(@fields) = split("\t");
    for (my $i=0;$i<@fields;$i++) {
      $max[$i] = length($fields[$i]) if
	$max[$i] < length($fields[$i]);
    }
  }
  foreach (@max) { $_ = 20 if $_ > 20; } # crunch long lines
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
  my @commands = "gif display @{[$self->class]} @{[$self->name]}";
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
sub right (\$) {
  my $self = shift;
  $self->_fill;
  $self->_parse;
  return $self->{'right'};
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
    my($self,$tag,$oldvalue) = @_;
    my $subtree = $self->at(($oldvalue ? "$tag.$oldvalue" : $tag),1);  # returns the parent
    if ("$subtree->{'right'}" eq $oldvalue) {
	$subtree->{'right'} = $subtree->{'right'}->down;
    } else {
	$subtree->{'down'} = $subtree->{'down'}->{'down'}
    }
    $oldvalue =~ s/([^a-zA-Z0-9_-])/\\$1/g;
    push(@{$self->{'delete'}},join(' ',split('\.',$tag),$oldvalue));
    delete $self->{'.PATHS'}; # uncache cached values
    1;
}

#############################################
#  follow into database #
sub pick (\$) {
    my $self = shift;
    my $thing_to_pick = ($self->class eq 'tag' && $self->right) ? $self->right : $self;
    return $thing_to_pick->_clone;
}

# returns true if the object has a Model, i.e, can be followed into
# the database.
sub isObject {
    my $self = shift;
    return undef if $self->class=~/^(float|int|date|tag|txt|dna|peptide|scalar)$/;
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
    my($self,$tag,$newvalue) = @_;
    return 1 if $self->at("$tag.$newvalue");  #already exists
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
    my($self,$tag,$oldvalue,$newvalue) = @_;
    $self->add($tag,$newvalue);
    $self->delete($tag,$oldvalue);
    delete $self->{'.PATHS'}; # uncache cached values
    1;
}

sub commit (\$) {
    my $self = shift;
    my (@cmd);
    push(@cmd,"parse = $self->{'class'} $self->{'name'} ; " . join(' ; ',@{$self->{'add'}}))
	if $self->{'add'};
    push(@cmd,"parse = $self->{'class'} $self->{'name'} ; -D " . join(' ; -D ',@{$self->{'delete'}}))
	if $self->{'delete'};
    warn join("\n",@cmd),"\n" if $self->debug && @cmd;
    return undef unless my $db = $self->db;

    foreach my $cmd (@cmd) {
	my $result = $db->raw_query($cmd);
	my ($errors) = $result =~ /(\d+) errors\/\/ \d+ Active Objects/;
	if ($errors) {
	    $ACE::ERR = "Error during commit().  Object $self->{name} not correctly written.";
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
    undef $self->{'right'};
}

sub debug {
    my $self = shift;
    return defined($_[0]) ? $self->{debug}=$_[0] : $self->{debug};
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
    return new Ace::Object($self->class,$self->name,$self->db);
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
  my $col = $self->{col};
  my $current_obj = $self;
  my $current_row = $self->{'start_row'};
  my $db = $self->{'db'};

  for (my $r=$self->{'start_row'}+1;$r<=$self->{'end_row'};$r++) {
    next unless $raw->[$r][$col];
    my $obj_on_right = $self->_fromRaw($raw,$current_row,$col+1,$r-1,$db);
    $current_obj->{'right'} = $obj_on_right;
    my $obj_down = $self->new($raw->[$r][$col]=~/^\?(.+)\?(.*)\?/,$db);
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
  my ($class,$name) = $raw->[$start_row][$col]=~/^\?(.+)\?(.*)\?/;
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
	s/\?[^?]*\?([^?]*)\?/$1/g;
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

sub _asHTML (\%\$$$;$) {
  my($self,$out,$position,$level,$morph_code) = @_;
  $$out .= "<TR ALIGN=LEFT>" unless $position;
  
  if ($self->{raw}) {  # we still have raw data, so we can optimize somewhat
    my ($a,$start,$end) = @{$self}{qw/col start_row end_row/};
    my @to_append = map { [@{$_}[$a..$#{$_}]] } @{$self->{'raw'}}[$start..$end];
    my $new_row;
    foreach my $row (@to_append) {
      if ($new_row++) {
	$$out .= "</TR>\n<TR ALIGN=LEFT>";
	$$out .= "<TD></TD>" x ($level-1) 
      }
      my @cells;
      if ($morph_code) {
	@cells = map { "<TD>" . 
			 ($_  ?  $morph_code->($self->new(/^\?(.+)\?(.*)\?/)) : '')
			     . "</TD>" } @$row;
      } else {
	@cells = map { /^\?(tag|[A-Z].*)\?/ ? "<TH>$_</TH>":"<TD>$_</TD>" } @$row;
	foreach (@cells) { s/\?[^?]*\?([^?]*)\?/$1/; }
      }
      $$out .= join('',@cells);
    }
    return $level-1;
  }

  $$out .= "<TD></TD>" x ($level-$position-1);
  my $cell;
  if ($morph_code) {
    $cell = "<TD>".$morph_code->($self)."</TD>";
  } else {
    my $tag = $self->isObject || $self->isTag ? "TH" : "TD";
    $cell = "<$tag>$self</$tag>";
  }
  $$out .= $cell;
  $level = $self->right->_asHTML($out,$level,$level+1,$morph_code)
    if $self->right;
  if ($self->down) {
    $$out .= "</TR>\n";
    $level = $self->down->_asHTML($out,0,$level);
  } else {
    $level--;
  }
  return $level;
}

# Return partial ace subtree at indicated tag
sub _at (\$$) {
    my ($self,$tag) = @_;
    my $p;
    my $o = $self->right;
    while ($o) {
	return ($o,$p,$self) if (lc($o) eq lc($tag));
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
    $i = $db->fetch(Sequence,'*');  # iteerate
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
    $r     = $sequence->at('Visible.Overlap_Right')->pick;
    $next  = $r->at('Visible.Overlap_left')->pick;

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
    print ACE->error;
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

Use Ace::connect() to establish a connection to an AceDB database.
The database must be up and running on the indicated host and port
prior to the connection attempt.  The full syntax is as follows:

    $db = Ace->connect(-host  =>  'sapiens.wustl.edu',
                       -port  =>  123456);

The connect() method uses a named argument calling style, and
recognizes the arguments B<-host> and B<-port>.  The host and port
correspond to the host and port of the ACE server.  Unlike previous
versions of this module, which required the presence of the aceclient
executable, all database connections are handled directly.

Note that the named argument style is just passing an associative
array to the subroutine.  

If arguments are omitted, they will default to the following values:

    -host         localhost
    -port         2000525

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

=head1 RETRIEVING ACEDB OBJECTS

Once you have established a connection and have an Ace databaes
handle, several methods can be used to query the ACE database to
retrieve certain objects.

=head2 list() method

    @sequences = $db->list(class,pattern);

This function queries the database for a list of objects matching the
specified class and pattern, returning a list of Ace::Objects.  The
class may be any class name recogized by the database's model.  The
pattern may be a full object identifier, or may contain wildcard
characters (* and ?).  For example, you can retrieve all Sequence
objects with this request:

    @sequences = $db->list('Sequence','*');

A limitation of this module is there is no way to iteratively retrieve
long lists of objects a chunk at a time.  This will be corrected
in a future implementation.

=head2 count() method

    $count = $db->list(class,pattern);

This function queries the database for a list of objects matching the
specified class and pattern, and returns the object count.  For large
sets of objects this is much more time and memory effective than
fetching the entire list.

The class and name pattern are the same as the list() method above.

=head2 fetch() method

    $object = $db->fetch(Sequence,'D12345');
    @objects = $db->fetch(Sequence,'D1234*');
    @objects = $db->fetch(Sequence,'Clone IS M4');

Ace::fetch() is similar to Ace::list(), but retrieves whole objects,
rather than a list.  It will either return a list of Ace::Objects, or
an empty list (or undef) in the case of an error.  Errors may occur
when the indicated object is not found in the database, if the
provided name contains wildcard characters, or if an error occurs
during communications.  A string describing the error can be found in
Ace->error.

When you know you need to retrieve and manipulate multiple objects, it
is faster to call fetch() with a pattern than to call list() and
manipulate the objects individually.  This is because list() returns
just the B<name> of the object, which is then filled in when needed.
Fetch() returns the B<entire> filled-in object.  There is latency
overhead every time you go back to the database.

As the last example shows, instead of providing a name pattern you can
fetch objects that meet the conditions of an arbitrary query language
expression.  Unfortunately, nobody currently understands the query
language syntax.

=head2 fetch_many() method

If you expect to retrieve many objects, you can fetch an iterator
across the data set.  This is friendly both in terms of network
bandwidth and memory consumption.  It is simple to use:

    $i = $db->fetch(Sequence,'*');  # all sequences!!!!
    while ($obj = $i->next) {
       print $obj->asTable;
    }

The iterator will return undef when it has finished iterating, and
cannot be used again.

=head2 raw_query() method

    $r = $db->raw_query('Model');

Send a command to the database and return its unprocessed output.
This method is necessary to gain access to features that are not yet
implemented in this module, such as model browsing and complex
queries.

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

    $object = new Ace::Object(class,name,database);

You can create a new Ace::Object from scratch by calling the new()
routine with the object's class, its identifier and a handle to the
database to create it in.  The object won't actually be created in the
database until you commit() it (see below).  If you do not provide a
database handle, the object will be created in memory only.

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

    $class = $object->name();

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

=head2 tags() method

     @tags = $object->tags();

Return all the top-level tags in the object as a list.  In the Author
example above, the returned list would be
('Full_name','Laboratory','Address','Paper').  

You can fetch tags more deeply nested in the structure by navigating
inwards using the methods listed below.

=head2 right() and down() methods

     $full_name = $object->right->right;
     $city = $object->right->down->down->right->right->down->down;

right() and down() provide a low-level way of traversing the tree
structure.  If $object contains the "Thierry-Mieg J" Author object,
then the first series of accesses shown above retrieves the string
"Jean Thierry-Mieg" and the second retrieves "34033 Montpellier."  If
the right or bottom pointers are NULL, these methods will return
undef.

In addition to being somewhat awkard, you will probably never need to
use these methods.  A simpler way to retrieve the same information
would be to use the at() method described in the next section.

If you do have need for this type of access, be aware that right() has
the potential to perform additional database accesses.  For example,
the node "FF" in the "Thierry-Mieg" object is actually a Laboratory
object that has additional database information associated with it.
Calling its right() method will bring this information into memory.
Therefore do not blindly follow the right() pointers until you hit
undef, as you may inadvertently traverse much of the database.  An
alternative that does B<not> cause additional database accesses is to
access the object as an associative array and use the "right" and
"down" keys.  This also has the advantage of being slightly faster.

    $object->{'right'};
    $object->{'down'};

=head2 at() method

    $subtree    = $object->at(tag_path);
    @values     = $object->at(tag_path);


at() is a simple way to fetch the portion of the tree that you are
interested in.  It takes a single argument, a simple tag or a
composite tag.  A simple tag, such as "Full_name", must correspond to
a tag in the column immediately to the right of the root of the tree.
A complex tag, such as "Address.Mail" is a dot-delimited path to the
subtree.  Some examples are given below.

    ($full_name)   = $object->at('Full_name');
    @address_lines = $object->at('Address.Mail');

The second line above is equivalent to:

    @address = $object->at('Address')->at('Mail');

Called without a tag name, at() just dereferences the object,
returning whatever is to the right of it, the same as
$object->{'right'}.

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

=head2 search() method

    $subtree    = $object->search(tag);
    @values     = $object->search(tag);

The search() method will perform a breadth-first search through the
object (columns first, followed by rows) for the tag indicated by the
argument, returning the column of the portion of the subtree it points
to.  For example, this code fragment will return the value of the
"Fax" tag.

    ($fax_no) = $object->search('Fax');

The list versus scalar context semantics are the same as in at(), so
if you want to retrieve the scalar value pointed to by the indicated
tag, either use a list context as shown in the example, above, or a
dereference, as in:

     $fax_no = $object->search('Fax')->at;

=head2 Autogenerated Access Methods

     ($fax_no) = $object->Fax;

The module attempts to autogenerate data access methods as needed.
For example, if you refer to a method named "Fax" (which doesn't
correspond to any of the built-in methods), then the code will call
the search() method to find a tag named "Fax" and return its
contents.  The list and scalar context semantics are the same as in
search().  

If no matching tag is found, the autogenerated method will return
undef or an empty array.

=head2 pick() method

    $new_object = $object->pick;

Follow object into the database, returning a new object.  This is
the best way to follow object references.  For example:

    $laboratory = $object->at('Laboratory')->pick;
    print $laboratory->asString;

=head2 col() method

     @address = $object->at('Address.Mail')->col(1);

col() is a low-level routine that returns the column of data to the
right of the object as a perl list.  Ordinarily col() will follow
database references.  If you provide it with an optional true
argument, this following will be suppressed.

=head2 row() method

     @row=$object->row();

row() is a low-level routine that routines the row of data to the
right of the object.  In the case of the "Thierry-Mieg J" object, the
example below will return the list ('Mail','CBM duCNRS').

     @row = $object->at('Address')->row();

=head2 asString() method

    $object->asString;

asString() returns a pretty-printed ASCII representation of the object
tree.

=head2 asTable() method

    $object->asTable;

asTable() returns a the object as a tab-delimited text table.

=head2 asHTML() method

   $object->asHTML;

asHTML() returns an HTML 3 table representing the object, suitable for
incorporation into a Web browser page.

=head2 add() method

    $result_code = $object->add(tag,value);    

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

    $result_code = $object->delete(tag_path,value);

Delete the indicated tag and value from the object.  This example
deletes the address line "FRANCE" from the Author's mailing address:

    $object->delete('Address.Mail','FRANCE');

No actual database deletion occurs until you call commit().  The
delete() result code indicates whether the deletion was successful.
Currently it is always true, since the database model is not checked.
    
=head2 replace() method

    $result_code = $object->replace(tag_path,oldvalue,newvalue);

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

=head1 BUGS

1. The ACE model should be consulted prior to updating the database.

2. There is no automatic recovery from connection errors.

3. Debugging has only one level of verbosity, despite the best
of intentions.

4. The module should connect directly to the Ace server via a
Jade netclient type of connection, rather than via a separate
aceclient process.

5. Performance is poor when fetching big objects, because of 
many object references that must be created.  This could be
improved.

6. Item number six is missing.

=head1 SEE ALSO

Jade Documentation

=head1 AUTHOR

Lincoln Stein <lstein@w3.org> with extensive help from Jean
Thierry-Mieg <mieg@kaa.crbm.cnrs-mop.fr>

Copyright (c) 1997, 1998, Lincoln D. Stein

This library is free software; 
you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut


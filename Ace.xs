#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include "aceclient.h"
#include "Ace.h"
#define CHUNKSIZE 10

#define metachar(c) (c == '\\' || c == '"' || c == '\t' || c == '\n' || c == '?')

static int
not_here(s)
char *s;
{
    croak("%s not implemented on this architecture", s);
    return -1;
}

static double
constant(name, arg)
char *name;
int arg;
{
    errno = 0;
    switch (*name) {
    case 'A':
	if (strEQ(name, "ACE_INVALID"))
#ifdef ACE_INVALID
	    return ACE_INVALID;
#else
	    goto not_there;
#endif
	if (strEQ(name, "ACE_OUTOFCONTEXT"))
#ifdef ACE_OUTOFCONTEXT
	    return ACE_OUTOFCONTEXT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "ACE_SYNTAXERROR"))
#ifdef ACE_SYNTAXERROR
	    return ACE_SYNTAXERROR;
#else
	    goto not_there;
#endif
	if (strEQ(name, "ACE_UNRECOGNIZED"))
#ifdef ACE_UNRECOGNIZED
	    return ACE_UNRECOGNIZED;
#else
	    goto not_there;
#endif
	if (strEQ(name, "ACE_PARSE"))
#ifdef ACE_PARSE
	    return ACE_PARSE;
#else
	    goto not_there;
#endif
	break;
    case 'B':
	break;
    case 'C':
	break;
    case 'D':
	if (strEQ(name, "DEFAULT_PORT"))
#ifdef DEFAULT_PORT
	    return DEFAULT_PORT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DROP_ENCORE"))
#ifdef DROP_ENCORE
	    return DROP_ENCORE;
#else
	    goto not_there;
#endif
	break;
    case 'E':
	break;
    case 'F':
	break;
    case 'G':
	break;
    case 'H':
	if (strEQ(name, "HAVE_ENCORE"))
#ifdef HAVE_ENCORE
	    return HAVE_ENCORE;
#else
	    goto not_there;
#endif
	break;
    case 'I':
	break;
    case 'J':
	break;
    case 'K':
	break;
    case 'L':
	break;
    case 'M':
	break;
    case 'N':
	break;
    case 'O':
	break;
    case 'P':
	break;
    case 'Q':
	break;
    case 'R':
	break;
    case 'S':
	if (strEQ(name, "STATUS_WAITING"))
#ifdef STATUS_WAITING
	    return STATUS_WAITING;
#else
	    goto not_there;
#endif
	if (strEQ(name, "STATUS_PENDING"))
#ifdef STATUS_PENDING
	    return STATUS_PENDING;
#else
	    goto not_there;
#endif
	if (strEQ(name, "STATUS_ERROR"))
#ifdef STATUS_ERROR
	    return STATUS_ERROR;
#else
	    goto not_there;
#endif
	break;
    case 'T':
	break;
    case 'U':
	break;
    case 'V':
	break;
    case 'W':
	if (strEQ(name, "WANT_ENCORE"))
#ifdef WANT_ENCORE
	    return WANT_ENCORE;
#else
	    goto not_there;
#endif
	break;
    case 'X':
	break;
    case 'Y':
	break;
    case 'Z':
	break;
    case '_':
	if (strEQ(name, "_ACECLIENT_"))
#ifdef _ACECLIENT_
	    return _ACECLIENT_;
#else
	    goto not_there;
#endif
	break;
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}

MODULE = Ace	PACKAGE = Ace

double
constant(name,arg)
	char *		name
	int		arg

MODULE = Ace	PACKAGE = Ace::AceDB

AceDB*
new(CLASS, host, rpc_port, timeOut=120)
	char*         CLASS
	char*         host
	unsigned long rpc_port
	int           timeOut
PREINIT:
	ace_handle* ace;
CODE:
	RETVAL = (AceDB*) safemalloc(sizeof(AceDB));
	if (RETVAL == NULL) XSRETURN_UNDEF;
	RETVAL->encoring = FALSE;
	RETVAL->status = STATUS_WAITING;
	RETVAL->answer = NULL;
	RETVAL->errcode = 0;
	ace = openServer(host,rpc_port,timeOut);
	if (ace == NULL) {
		safefree(RETVAL);
		XSRETURN_UNDEF;
	} else {
		RETVAL->database = ace;
	}
OUTPUT:
	RETVAL

void
DESTROY(self)
	AceDB* self
CODE:
	if (self->answer != NULL)
	   free((void*) self->answer);
	if (self->database != NULL)
	   closeServer(self->database);
	safefree((char*)self);

ace_handle*
handle(self)
	AceDB* self
CODE:
	RETVAL = self->database;
OUTPUT:
	RETVAL

int
encore(self)
	AceDB* self
CODE:
	RETVAL = self->encoring;
OUTPUT:
	RETVAL

int
error(self)
	AceDB* self
CODE:
	RETVAL = self->errcode;
OUTPUT:
	RETVAL

int
status(self)
	AceDB* self
CODE:
	RETVAL = self->status;
OUTPUT:
	RETVAL

int
query(self,request, encore=0)
	AceDB* self
	char*  request
	int    encore
PREINIT:
	unsigned char* answer = NULL;
	int retval,length,isWrite;
CODE:
	isWrite = encore == 3;
	retval = askServerBinary(self->database,request,
	                         &answer,&length,&encore,CHUNKSIZE);
	if (self->answer) {
	   free((void*) self->answer);
	   self->answer = NULL;
	}
	self->errcode = retval;
        self->status = STATUS_WAITING;
	if ((retval > 0) || (answer == NULL) ) {
	   self->status = STATUS_ERROR;
	   RETVAL = 0;
	} else {
	   self->answer = answer;
	   self->length = length;
           self->status = STATUS_PENDING;
	   self->encoring = encore && !isWrite;
	   RETVAL = 1;
        }
OUTPUT:
	RETVAL

SV*
read(self)
	AceDB* self
PREINIT:
	unsigned char* answer = NULL;
	int retval,length,encore=0;
CODE:
	if (self->status != STATUS_PENDING)
	   XSRETURN_UNDEF;

	if (self->answer == NULL && self->encoring) {
	  retval = askServerBinary(self->database,"encore",&answer,
                                    &length,&encore,CHUNKSIZE);
	  self->errcode = retval;
	  self->encoring = encore;
	  if ((retval > 0) || (answer == NULL) ) {
	    self->status = STATUS_ERROR;
	    XSRETURN_UNDEF;
	  }
	  self->answer = answer;
	  self->length = length;
	}
        if (!self->encoring) 
           self->status = STATUS_WAITING;
	RETVAL = newSVpv((char*)self->answer,self->length);
OUTPUT:
	RETVAL
CLEANUP:
	if (self->answer != NULL) {
	   free((void*) self->answer);
	   self->length = 0;
	   self->answer = NULL;
	}

SV*
freeprotect(CLASS,string)
     char*  CLASS
     char*  string
PREINIT:
	unsigned long count = 2;
	char *cp,*new,*a;
CODE:
	/* count the number of characters that need to be escaped */
	for (cp = string; *cp; cp++ ) {
	   count += metachar(*cp) ? 2 : 1;
	   if (*cp == '\n') count += 2;
	}

	/* create a new char* large enough to hold the result */
	New(0,new,count+1,char);
	if (new == NULL) XSRETURN_UNDEF;
	a = new;
	*a++ = '"';
	cp = string;
	for (cp = string; *cp; *a++ = *cp++) {
	   if (metachar(*cp)) *a++ = '\\';
	   if (*cp == '\n') { *a++ = 'n' ; *a++ = '\\'; }
	}
	*a++ = '"';
	*a++ = '\0';
	RETVAL = newSVpv("",0);
	sv_usepvn(RETVAL,new,count);
OUTPUT:
	RETVAL

void
split(CLASS,string)
     char*  CLASS
     char*  string
PREINIT:
	char *class,*name,*cp,*dest;
	SV* c,n;
	int class_size,name_size,total_size;
PPCODE:
	if (*string != '?') XSRETURN_EMPTY;
	/* first scan for the class */
	total_size = strlen(string) + 1;
	Newz(0,class,total_size,char);
	SAVEFREEPV(class);

	for (cp = string+1,dest=class; *cp; *cp && (*dest++ = *cp++) ) {
		while (*cp && *cp == '\\') {
			cp++;             /* skip character */
			if (!*cp) break;
			if (*cp == 'n') {
			  *dest++ = '\n';
			  cp++;
			}
			else if (*cp == 't') {
			  *dest++ = '\t';
			  cp++;
			}
			else
			  *dest++ = *cp++; /* copy next character */
		}
		if (*cp == '?') break;
	}
	*dest = '\0';  /* paranoia */
	if (!*cp) XSRETURN_EMPTY;

	/* dest should now point at the '?' character, and class holds
	the class name */
	class_size = dest-class;

	/* now we go after the object name */
	total_size -= (cp - string);
	Newz(0,name,total_size,char);
	SAVEFREEPV(name);

	for (++cp, dest=name; *cp ; *cp && (*dest++ = *cp++) ) {
		while (*cp && *cp == '\\') {
		  cp++;             /* skip character */
		  if (!*cp) break;
		  if (*cp == 'n') {
		    *dest++ = '\n';
		    cp++;
		  }
		  else if (*cp == 't') {
		    *dest++ = '\t';
		    cp++;
		  }
		  else
		    *dest++ = *cp++; /* copy next character */
		}
		if (*cp == '?') break;
	}
	*dest = '\0';
	if (!*cp) XSRETURN_EMPTY;

	name_size = dest - name;
	EXTEND(sp,2);
	PUSHs(sv_2mortal(newSVpv(class,class_size)));
	PUSHs(sv_2mortal(newSVpv(name,name_size)));

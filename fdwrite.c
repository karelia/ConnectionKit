/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#include <sys/types.h>
#include <sys/param.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "fdwrite.h"

extern int		errno;
typedef unsigned short 	unichar;

/* write arbitrary formatted string to an open file descriptor */
    int
fdwrite( int fd, char *format, ... )
{
    va_list	val;
    unichar	line[ LINE_MAX ];
    
//    if ( ! connected ) {
//	syslog( LOG_ERR, "Attempted write while not connected!" );
//	return( -1 );
//    }
    
#ifdef __STDC__
    va_start( val, format );
#else
    va_start( val );
#endif /* __STDC__ */

    if ( vsnprintf(( char * )line, LINE_MAX, format, val ) > ( LINE_MAX - 1 )) {
	syslog( LOG_ERR, "Line to write is too long!" );
	return( -1 );
    }
    
    va_end( val );
    
    if ( write( fd, line, strlen(( char * )line )) != strlen(( char * )line )) {
	syslog( LOG_ERR, "Wrote wrong number of bytes to file descriptor." );
	return( -1 );
    }
    
    return( 0 );
}
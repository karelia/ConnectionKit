/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#include <stdlib.h>

#include "argcargv.h"

#define ACV_ARGC		10
#define ACV_WHITE		0
#define ACV_WORD		1
static ACAV *acavg = NULL;

    ACAV*
acav_alloc( void )
{
    ACAV *acav;

    if ( ( acav = (ACAV*)malloc( sizeof( ACAV ) ) ) == NULL ) {
	return( NULL );
    }
    acav->acv_argv = NULL;
    if ( ( acav->acv_argv =
	    (char **)malloc( sizeof(char *) * ( ACV_ARGC ) ) ) == NULL ) {
	return( NULL );
    }
    acav->acv_argc = ACV_ARGC;

    return( acav );
}

/*
 * acav->acv_argv = **argv[] if passed an ACAV
 */

    int
acav_parse( ACAV *acav, char *line, char **argv[] )
{
    int		ac;
    int		state;

    if ( acav == NULL ) {
	if ( acavg == NULL ) {
	    acavg = acav_alloc();
	}
	acav = acavg;
    }

    ac = 0;
    state = ACV_WHITE;

    for ( ; *line != '\0'; line++ ) {
	switch ( *line ) {
	case ' ' :
	case '\t' :
	case '\n' :
        case '\r' :
	    if ( state == ACV_WORD ) {
		*line = '\0';
		state = ACV_WHITE;
	    }
	    break;
	default :
	    if ( state == ACV_WHITE ) {
		acav->acv_argv[ ac++ ] = line;
		if ( ac >= acav->acv_argc ) {
		    /* realloc */
		    if (( acav->acv_argv = (char **)realloc( acav->acv_argv,
			    sizeof( char * ) * ( acav->acv_argc + ACV_ARGC )))
			    == NULL ) {
			return( -1 );
		    }
		    acav->acv_argc += ACV_ARGC;
		}
		state = ACV_WORD;
	    }
	}
    }

    acav->acv_argv[ ac ] = NULL; 
    *argv = acav->acv_argv;
    return( ac );
}

    int
acav_free( ACAV *acav )
{
    free( acav->acv_argv );
    free( acav );

    return( 0 );
}

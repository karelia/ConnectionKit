/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#include <CoreFoundation/CoreFoundation.h>

#include <sys/param.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>
#include "sshversion.h"

extern int	errno;

    int
sshversion()
{
    const CFStringRef   user = kCFPreferencesCurrentUser;
    const CFStringRef   host = kCFPreferencesAnyHost;
    CFStringRef         appID = CFSTR( "edu.umich.fugu" );
    CFStringRef         key = CFSTR( "ExecutableSearchPath" );
    CFStringRef         sshbinary = NULL;
    CFRange             range = { 0, 0 };
    struct stat         st;
    int                 efd[ 2 ];
    char                *sshexec[] = { NULL, NULL, NULL }, *p;
    char                line[ MAXPATHLEN ], sshpath[ MAXPATHLEN ] = { 0 };
    int                 estatus, rr;
    
    if (( sshbinary = CFPreferencesCopyValue( key, appID, user, host )) == NULL ) {
        strcpy( sshpath, "/usr/bin/ssh" );
    } else {
        range.length = CFStringGetLength( sshbinary );
        if ( CFStringGetBytes( sshbinary, range, kCFStringEncodingUTF8, '?',
                                FALSE, (UInt8 *)sshpath, MAXPATHLEN, NULL ) == 0 ) {
            syslog( LOG_ERR, "CFStringGetBytes failed" );
            strcpy( sshpath, "/usr/bin/ssh" );
        } else {
            if ( strlen( sshpath ) + strlen( "/ssh" ) >= MAXPATHLEN ) {
                syslog( LOG_ERR, "%sssh: too long", sshpath );
				CFRelease( sshbinary );
                return( -1 );
            }
            strcat( sshpath, "/ssh" );
        }
        CFRelease( sshbinary );
    }
    
    if ( stat( sshpath, &st ) < 0 ) {
        syslog( LOG_ERR, "stat %s: %m", sshpath );
        return( -1 );
    }
    if ( ! S_ISREG( st.st_mode ) ||
            ! ( st.st_mode & ( S_IRUSR | S_IXUSR ))) {
        syslog( LOG_ERR, "%s cannot be executed", sshpath );
        return( -1 );
    }
    
    if ( pipe( efd ) < 0 ) {
        syslog( LOG_ERR, "pipe: %s", strerror( errno ));
        return( -1 );
    }
    
    sshexec[ 0 ] = sshpath;
    sshexec[ 1 ] = "-V";
    sshexec[ 2 ] = NULL;
    
    switch ( fork()) {
    case 0:
        if ( dup2( efd[ 1 ], 2 ) < 0 ) {
            syslog( LOG_ERR, "dup2: %s", strerror( errno ));
            break;
        }
        ( void )close( efd[ 0 ] );
        ( void )close( efd[ 1 ] );
        
        execve( sshpath, ( char ** )sshexec, NULL );
        syslog( LOG_ERR, "execve ssh -V: %s", strerror( errno ));
        break;
        
    case -1:
        ( void )close( efd[ 0 ] );
        ( void )close( efd[ 1 ] );
        syslog( LOG_ERR, "fork failed: %s", strerror( errno ));
        exit( 2 );
        
    default:
        break;
    }
    
    ( void )close( efd[ 1 ] );
    rr = read( efd[ 0 ], line, MAXPATHLEN );
    if ( rr < 0 ) {
        syslog( LOG_ERR, "read returned < 0: %s", strerror( errno ));
        return( -1 );
    }
    
    line[ rr ] = '\0';
    syslog( LOG_INFO, line );
    
    wait( &estatus );

    if (( p = strstr( line, "OpenSSH" )) == NULL ) {
        /* maybe we're dealing with an SSH.com version */
        if (( p = strstr( line, "SSH Secure Shell" )) != NULL ) {
            return( SFTP_VERSION_UNSUPPORTED );
        }
        return( -1 );
    }
    
    if (( p = strchr( line, '_' )) == NULL ) {
        return( -1 );
    }
    
    p++;
    if ( p != NULL ) {
        double	ver;
        int		i;
        char	tmp[ 4 ];
        
        for ( i = 0; i < 3; i++ ) 
		{
            if (!*p) break;
            tmp[ i ] = *p;
            p++;
        }
	
        ver = strtod( tmp, NULL );
        
        if ( ver < 3.5 ) {
            return( SFTP_LS_SHORT_FORM );
        } else if ( ver >= 3.9 ) {
            return( SFTP_LS_EXTENDED_LONG_FORM );
        }
        
        return( SFTP_LS_LONG_FORM );
    }
    
    return( -1 );
}

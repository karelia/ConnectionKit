/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPTServer.h"
#import "SFTPConnection.h"
#import "NSArray+Connection.h"
#import "NSString+Connection.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <util.h>

#include "argcargv.h"
#include "fdwrite.h"
#include "typeforchar.h"

extern int	errno;
char	**environ;

/* used to set which field contains the filename */
static int      filenameIndexDistanceFromEnd = -1;

@implementation SFTPTServer

+ ( void )connectWithPorts: ( NSArray * )ports
{
    NSAutoreleasePool		*pool = [[ NSAutoreleasePool alloc ] init ];
    NSConnection		*cnctnToController;
    SFTPTServer			*serverObject;
    
    cnctnToController = [ NSConnection connectionWithReceivePort:
                            [ ports objectAtIndex: 0 ]
                            sendPort: [ ports objectAtIndex: 1 ]];
                            
    serverObject = [[ self alloc ] init ];
    [ (( SFTPConnection * )[ cnctnToController rootProxy ] ) setServerObject: serverObject ];
    [ serverObject release ];
    
    [[ NSRunLoop currentRunLoop ] run ];  
    [ pool release ];
}

- ( id )init
{
    _currentTransferPath = nil;
    _sftpRemoteObjectList = nil;
	
	cancelflag = 0;
	sftppid = 0;
	connecting = NO;
	connected = 0;
	master = 0;
	
    
    return(( self = [ super init ] ) ? self : nil );
}

/* accessor methods */
- (void)forceDisconnect
{
	cancelflag = YES;
}
- ( void )setCurrentTransferPath: ( NSString * )name
{
    if ( _currentTransferPath != nil ) {
	[ _currentTransferPath release ];
	_currentTransferPath = nil;
    }
    
    if ( name != nil ) {
	_currentTransferPath = [[ NSString alloc ] initWithString: name ];
    } else {
	_currentTransferPath = name;
    }
}

- ( NSString * )currentTransferPath
{
    return( _currentTransferPath );
}

- ( id )remoteObjectList
{
    return( _sftpRemoteObjectList );
}

- ( void )setRemoteObjectList: ( id )objectList
{
    if ( _sftpRemoteObjectList ) {
        [ _sftpRemoteObjectList release ];
        _sftpRemoteObjectList = nil;
    }
    if ( ! objectList ) {
        return;
    }
    
    _sftpRemoteObjectList = [ objectList retain ];
}
/* end accessor methods */

/* sftp/ftp output handler methods */
- ( BOOL )hasPasswordPromptInBuffer: ( char * )buf
{
#ifdef notdef
    NSArray             *prompts = nil;
#endif /* notdef */
    BOOL                hasPrompt = NO;
    int                 i, pnum = 0;
    char                *prompts[] = { "password", "Password:", "PASSCODE:", "Password for ", "Passcode for ", "CryptoCard Challenge" };
                                    
    if ( buf == NULL ) {
        return( NO );
    }
    
    pnum = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < pnum; i++ ) {
        if ( strstr( buf, prompts[ i ] ) != NULL ) {
            hasPrompt = YES;
            break;
        }
    }
    
#ifdef notdef
    /* someday we'll allow custom prompt checks */
#endif /* notdef */
    
    return( hasPrompt );
}

- ( BOOL )bufferContainsError: ( char * )buf
{
    BOOL                hasError = NO;
    int                 i, numerrs = 0;
    char                *errors[] = {"Permission denied", "Couldn't ", "Secure connection ", "No address associated with", "Connection refused", "Request for subsystem", "Cannot download", "ssh_exchange_identification", "Operation timed out", "no address associated with", "Error: "};
                                    
    if ( buf == NULL ) {
        return( NO );
    }
                                    
    numerrs = ( sizeof( errors ) / sizeof( errors[ 0 ] ));
    for ( i = 0; i < numerrs; i++ ) {
        if ( strstr( buf, errors[ i ] ) != NULL ) {
            hasError = YES;
            break;
        }
    }
    
    return( hasError );
}

- ( BOOL )hasDirectoryListingFormInBuffer: ( char * )buf
{
    BOOL                hasDirListForm = NO;
    int                 i, numforms = 0;
    char                *lsforms[] = { "ls -l", "ls", "ls " };
    
    if ( buf == NULL ) {
        return( NO );
    }
    
    numforms = ( sizeof( lsforms ) / sizeof( lsforms[ 0 ] ));
    for ( i = 0; i < numforms; i++ ) {
        if ( strncmp( buf, lsforms[ i ], strlen( lsforms[ i ] )) == 0 ) {
            hasDirListForm = YES;
            break;
        }
    }
    
    return( hasDirListForm );
}

- ( BOOL )unknownHostKeyPromptInBuffer: ( char * )buf
{
    BOOL                isPrompt = NO;
    int                 i, numprompts = 0;
    char                *prompts[] = { "The authenticity of ",
                                        "Host key not found " };
                                        
    numprompts = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < numprompts; i++ ) {
        if ( strncmp( buf, prompts[ i ], strlen( prompts[ i ] )) == 0 ) {
            isPrompt = YES;
            break;
        }
    }
    
    return( isPrompt );
}

- ( void )parseTransferProgressString: ( char * )string isUploading: ( BOOL )uploading
	forWrapperConnection: ( SFTPConnection * )wrapperConnection
{	
    int			tac, i, pc_index = -1;
    char		*tmp, **tav, *p;
    char		*t_rate, *t_amount, *t_eta;
    
    if (( tmp = strdup( string )) == NULL ) {
	perror( "strdup" );
	exit( 2 );
    }
    
    if (( tac = argcargv( tmp, &tav )) < 5 ) {
	/* not a transfer progress line we're interested in */
	free( tmp );
	return;
    }
    
    for ( i = ( tac - 1 ); i >= 0; i-- ) {
	if (( p = strrchr( tav[ i ], '%' )) != NULL ) {
	    /* found the %-done field */
	    pc_index = i;
	    p = '\0';
	    break;
	}
    }
    
    t_amount = tav[ pc_index + 1 ];
    t_rate = tav[ pc_index + 2 ];
    
    if ( pc_index == ( tac - 5 )) {
	t_eta = tav[ pc_index + 3 ];
    } else {
	t_eta = "--:--";
    }
	
	double progressPercentage = strtod(tav[pc_index], NULL);
	NSString *transferRate = [NSString stringWithUTF8String:t_rate];
	NSString *eta = [NSString stringWithFormat:@"%s", t_eta];	
	
	NSString *formattedAmountString = [NSString stringWithUTF8String:t_amount];
	char *amountCharacter;
	unsigned int baseMultiplier = 1.0;
	if ([formattedAmountString hasSuffix:@"KB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 1);
	}
	else if ([formattedAmountString hasSuffix:@"MB"])
	{
		NSString *numberOfMBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfMBString UTF8String];
		baseMultiplier = pow(1024, 2);
	}
	else if ([formattedAmountString hasSuffix:@"GB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 3);
	}	
	else if ([formattedAmountString hasSuffix:@"TB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 3);
	}	
	else
	{
		amountCharacter = t_amount;
	}
	
	unsigned long long amountTransferred = strtoull(amountCharacter, NULL, 0);
	amountTransferred *= baseMultiplier;
    if ( uploading ) 
	{
		[wrapperConnection upload:[wrapperConnection currentUploadInfo] didProgressTo:progressPercentage withEstimatedCompletionIn:eta givenTransferRateOf:transferRate amountTransferred:amountTransferred];
    }
	else
	{
		[wrapperConnection download:[wrapperConnection currentDownloadInfo] didProgressTo:progressPercentage withEstimatedCompletionIn:eta givenTransferRateOf:transferRate amountTransferred:amountTransferred];		
    }
    
    free( tmp );
}
/* end sftp/ftp output handler methods */

- ( pid_t )getSftpPid
{
    return( sftppid );
}

- ( int )atSftpPrompt
{
    return( atprompt );
}

- ( NSString * )retrieveUnknownHostKeyFromStream: ( FILE * )stream
{
    NSString            *key = @"";
    char                buf[ MAXPATHLEN * 2 ];
    
    if ( fgets( buf, MAXPATHLEN * 2, stream ) == NULL ) {
        NSLog( @"fgets: %s\n", strerror( errno ));
    } else if (( key = [ NSString stringWithUTF8String: buf ] ) == nil ) {
        key = @"";
    }
    
    return( key );
}

- ( NSMutableDictionary * )remoteObjectFromSFTPLine: ( char * )object
{
	int fncolumn = -1;
    int			j, tac, len;
    int			datecolumn = -1, ownercolumn = 2;
    char                line[ MAXPATHLEN * 2 ] = { 0 };
    char                *filename = NULL;
    char		**targv;
    char                *p;
    NSMutableDictionary	*infoDictionary = nil;
    NSString		*dateString = nil, *groupName = nil, *name = nil;
    NSData              *nameAsRawBytes = nil;

    if ( strncmp( object, "sftp> ", strlen( "sftp> " )) == 0 ) {
        return( nil );
    }
    
    if ( strlen( object ) >= sizeof( line )) {
        NSLog( @"%s: too long\n", object );
        return( nil );
    }
    strcpy( line, object );
    
    /* break up the string into components */
    if (( tac = argcargv( line, &targv )) <= 0 ) {
        return( nil );
    }
    
    /* 
     * much of the abstraction in here to handle an arbitrary number of fields
     * was suggested by Hugues Martel. He used Obj-C calls. C calls are used here,
     * since otherwise there's a lot of unnecessary conversion.
     * Many thanks to Hugues for this contribution.
     */
        
    /* SSH.com's sftp gives true ls -lF output. 		*/
    /* Do we need to add other chars here (>, /, @, =)? 	*/
    if ( tac > 0 ) {
	p = targv[ ( tac - 1 ) ];
	len = strlen( p );
	if ( len > 1 && *targv[ 0 ] == '-' && p[ len - 1 ] == '*' ) {
            p[ len - 1 ] = '\0';
        }
    }
    
    /* SSH.com's sftp client writes dir name + : before listing */
    if ( tac == 1 && strcmp( targv[ 0 ], ".:" ) == 0 ) {
		filenameIndexDistanceFromEnd = tac - 8;
        goto DOT_OR_DOTDOT;
    } else if ( tac == 1 ) {
	/* prevent crashes */
	goto DOT_OR_DOTDOT;
    }
    
    /*
     * find the filename column. The first line should contain
     * a filename '.' or './'.
     */
    for ( j = 0; j < tac; j++ ) {
        if ( strcmp( targv[ j ], "." ) == 0 || strcmp( targv[ j ], "./" ) == 0 ) {
			filenameIndexDistanceFromEnd = tac - j;
            fncolumn = j;
            break;
        }
    }
	fncolumn = tac - filenameIndexDistanceFromEnd;
    /* likewise, determine how many fields are used for the date.	*/
    /* based on code submitted by Hugues Martel.			*/
    if ( fncolumn == -1 ) {
        /* probably an invalid line, but might also be a VShell-like    */
        /* server at the root directory.				*/
        if ( isdigit( *targv[ 0 ] ) && strchr( targv[ 4 ], ':' ) != NULL ) {
            fncolumn = 5;
        } else if ( *targv[ 0 ] == 'd' || *targv[ 0 ] == '-'
                    && tac >= 9 ) {
            /* might also be OpenSSH on Cygwin, which doesn't display	*/
            /* a '.' or './' at the root directory. if so, handle it.	*/
            fncolumn = 8;
        }
    }
    if ( fncolumn == -1 || fncolumn > tac ) {
        return( nil );			/* invalid output */
    }

    for ( j = ( fncolumn - 1 ); j >= 0; j-- )
	{
        if ( isalpha( *targv[ j ] ))
		{ 	/* we've found the column containing the month */
            datecolumn = j;
            if ( datecolumn != 5 )
			{
                int             ind = 0;
                
//                NSLog( @"datecolumn: %d\tdate: %s", datecolumn, targv[ j ] );
//                for ( ind = 0; ind < tac; ind++ )
//				{
//                    NSLog( @"targv[ %d ]: %s", ind, targv[ ind ] );
//                }
//                NSLog( @"line: %s", object );
            }
            break;
        }
    }
    if ( datecolumn < 0 ) {	/* potentially dealing with old OpenSSH version */
        if ( *targv[ 0 ] == '0' && strlen( targv[ 0 ] ) > 1
                                && strchr( targv[ 4 ], ':' ) == NULL
                                && fncolumn == 5 ) {
            datecolumn = ( fncolumn - 1 );
            ownercolumn = 1;
        }
    }
    if ( datecolumn >= tac || datecolumn < 0 ) {
        return( nil );
    }
            
    dateString = [ NSString stringWithUTF8String: targv[ datecolumn ]];
    for ( j = ( datecolumn + 1 ); j < fncolumn; j++ ) {
        dateString = [ NSString stringWithFormat: @"%@ %s", dateString, targv[ j ]];
    }
    infoDictionary = [[ NSMutableDictionary alloc ] init ];
    [ infoDictionary setObject: dateString forKey: @"date" ];
    
    if ( datecolumn >= 1 ) {    /* size always comes before date */
        [ infoDictionary setObject: [ NSString stringWithUTF8String:
                                        targv[ ( datecolumn - 1 ) ]]
                            forKey: @"size" ];
    }
        
    if ( fncolumn > 0 && tac >= ( fncolumn + 1 )) {
        if ( tac > ( fncolumn + 1 )) {
            if ( strstr( targv[ 0 ], "sftp>" ) != NULL ) {
                goto DOT_OR_DOTDOT;
            }
            
            for ( j = fncolumn; j < tac; j++ ) {
                len += ( strlen( targv[ j ] ) + 1 );    /* +1 for spaces */
            }

            if (( filename = ( char * )malloc( len )) == NULL ) {
                NSLog( @"malloc: %s", strerror( errno ));
                exit( 2 );
            }
            strlcpy( filename, targv[ fncolumn ], len );
            
            for ( j = fncolumn + 1; j < tac; j++ ) {
                if ( strcmp( targv[ j ], "->" ) == 0 ) {
                    break;
                }
                strlcat( filename, " ", len );
                strlcat( filename, targv[ j ], len );
            }
            
            nameAsRawBytes = [ NSData dataWithBytes: filename length: strlen( filename ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: filename
                                                    length: strlen( filename ) ];
            free( filename );
        } else {
            if ( strcmp( ".", targv[ fncolumn ] ) == 0
                    || strcmp( "./", targv[ fncolumn ] ) == 0 /* VShell output */
                    || strcmp( "../", targv[ fncolumn ] ) == 0
                    || strcmp( "..", targv[ fncolumn ] ) == 0 ) goto DOT_OR_DOTDOT;
            
            nameAsRawBytes = [ NSData dataWithBytes: targv[ fncolumn ]
                                length: strlen( targv[ fncolumn ] ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: targv[ fncolumn ]
                                            length: strlen( targv[ fncolumn ] ) ];
        }

        if (( datecolumn - 1 ) == 0 ) {		/* dealing with a VShell server, probably. */
            [ infoDictionary setObject: @"N/A" forKey: @"owner" ];
            [ infoDictionary setObject: @"N/A" forKey: @"group" ];
            /* since VShell doesn't include a mode, we have to invent one */
            /* based on code submitted by Hugues Martel. */
            if ( [ name characterAtIndex: ( [ name length ] - 1 ) ] == '/' ) { /* directory */
                [ infoDictionary setObject: @"d---------" forKey: @"perm" ];
                [ infoDictionary setObject: @"directory" forKey: @"type" ];
            } else {
                [ infoDictionary setObject: @"----------" forKey: @"perm" ];
                [ infoDictionary setObject: @"file" forKey: @"type" ];
            }
        } else if (( datecolumn - 1 ) > 1 ) {	/* probably some unix variant */
            [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ ownercolumn ]]
                                    forKey: @"owner" ];
            groupName = [ NSString stringWithUTF8String: targv[ ( ownercolumn + 1 ) ]];
            /* possible to have group names containing spaces */
            for ( j = ( ownercolumn + 2 ); j < ( datecolumn - 1 ); j++ ) {
                groupName = [ NSString stringWithFormat: @"%@ %s", groupName, targv[ j ]];
            }
            [ infoDictionary setObject: groupName forKey: @"group" ];

            /* handle old OpenSSH server by translating output */
            if (( datecolumn + 1 ) == fncolumn && *targv[ 0 ] == '0' ) {
                [ infoDictionary setObject:
                                    [[ NSString stringWithUTF8String: targv[ 0 ]]
                                        stringRepresentationOfOctalMode ]
                                    forKey: @"perm" ];
            } else {
                [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ 0 ]]
                                    forKey: @"perm" ];
            }
            [ infoDictionary setObject:
                [ NSString stringWithUTF8String:
                typeforchar( [[ infoDictionary objectForKey: @"perm" ] characterAtIndex: 0 ] ) ]
                            forKey: @"type" ];
        }
        [ infoDictionary setObject: name forKey: @"name" ];
        [ infoDictionary setObject: nameAsRawBytes forKey: @"NameAsRawBytes" ];
    }
    
    return( [ infoDictionary autorelease ] );
    
DOT_OR_DOTDOT:
    if ( infoDictionary ) {
        [ infoDictionary release ];
    }
    return( nil );
}
- (BOOL)buffer:(char *)buffer containsString:(char *)stringCheck
{
	return strstr(buffer, stringCheck) != NULL;
}
- (oneway void)connectToServerWithParams:(NSArray *)params fromWrapperConnection:(SFTPConnection *)sftpWrapperConnection
{
	NSString *sftpBinaryPath = [NSString pathForExecutable:@"sftp"];
	if (!sftpBinaryPath)
	{
		NSLog(@"Could Not Find SFTP Binary Path");
		return;
	}
	
	//Construct the initial argument
	[sftpWrapperConnection logForCommandQueue:[NSString stringWithFormat:@"Dispatching \"sftp %@\"", [params componentsJoinedByString:@" "]]];
	NSArray *passedInArguments = [params copy];
	NSArray *commandArguments = [NSArray arrayWithObject:sftpBinaryPath];
	commandArguments = [commandArguments arrayByAddingObjectsFromArray:passedInArguments];
	char **executableArguments;
	[commandArguments createArgv:&executableArguments];
	[passedInArguments release];
	
	connecting = YES;	
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"sftp launch path is %s.\n", executableArguments[0]]];
	
	char teletypewriterName[MAXPATHLEN];
	struct winsize windowSize = {24, 512, 0, 0};
	sftppid = forkpty(&master, teletypewriterName, nil, &windowSize);
	switch (sftppid)
	{
		case 0:
			//SFTP could not be launched
			execve(executableArguments[0], executableArguments, environ);			
			NSLog(@"Could not launch SFTP: %s", strerror(errno));
			_exit(2);
			
		case -1:
			//Error with forkpty()
			NSLog(@"forkpty error: %s", strerror(errno));
			exit(2);
			
		default:
			break;
	}
	[sftpWrapperConnection setMasterProxy:master];
	
	//Ensure the Master doesn't block
	if (fcntl(master, F_SETFL, O_NONBLOCK) < 0)
	{
		//There was an error ensuring we didn't block
		NSLog(@"fcntl non-block instruction failed with error: %s", strerror(errno));
	}
	
	//Open the stream
	FILE *masterFileStream = fdopen(master, "r+");
	if (!masterFileStream)
	{
		//Failed to open stream using fdopen
		NSLog(@"Failed to open file stream using fdopen: %s", strerror(errno));
		return;
	}
	//Associate our new file stream
	setvbuf(masterFileStream, nil, _IONBF, 0);
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"Slave terminal device is %s.\n", teletypewriterName]];
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"Master Device is %d.\n", master]];
	
	fd_set readMask;
	char serverResponseBuffer[MAXPATHLEN *2];
	BOOL hasValidPassword = NO, passwordWasSent = NO, homeDirectoryWasSet = NO, wasChanging = NO, wasListing = NO, atSFTPPrompt = NO;
	while (1)
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if (cancelflag)
		{
			[pool release];
			pool = nil;
			break;
		}		
		
		FD_ZERO(&readMask);
		FD_SET(master, &readMask);
		
		switch(select(master+1, &readMask, nil, nil, nil))
		{
			case -1:
				//Error
				NSLog(@"Select Error:%s", strerror(errno));
				break;
				
			case 0:
				//This is a timeout
				continue;
				
			default:
				break;
		}
		
		if (FD_ISSET(master, &readMask))
		{
			if (!fgets((char *)serverResponseBuffer, MAXPATHLEN, masterFileStream))
			{
				break;
			}
		}
		
		[sftpWrapperConnection logServerResponseBuffer:[NSString stringWithFormat:@"ServerResponseBuffer: %s", (char *)serverResponseBuffer]];
		if (serverResponseBuffer[0] != '\0')
		{
			[sftpWrapperConnection addStringToTranscript:[NSString stringWithUTF8String:serverResponseBuffer]];
		}
		
		if ([self hasPasswordPromptInBuffer:serverResponseBuffer] && !hasValidPassword && connecting)
		{
			[sftpWrapperConnection requestPasswordWithPrompt:(char *)serverResponseBuffer];
			passwordWasSent = YES;
		}
		else if (strstr(serverResponseBuffer, "sftp> ") != nil)
		{
			//We are waiting at the SFTP Prompt.
			
			atSFTPPrompt = YES;
			if (!connected)
			{
				passwordWasSent = YES;
				hasValidPassword = YES;
				connecting = 0;
				connected = 1;
				[sftpWrapperConnection didConnect];
			}
			else if (!homeDirectoryWasSet)
			{
//				[sftpWrapperConnection updateCurrentWorkingDirectory];
				homeDirectoryWasSet = YES;
			}
			else if (wasChanging)
			{
				[sftpWrapperConnection directoryContents];
				wasChanging = NO;
			}
			
			else if (wasListing)
			{
				wasListing = NO;
			}
			[sftpWrapperConnection finishedCommand];
		}
		else
		{
			atSFTPPrompt = NO;
			
			if (strncmp((char *)serverResponseBuffer, "Permission denied, ", strlen("Permission denied, ")) == 0)
			{
				[sftpWrapperConnection passwordErrorOccurred];
				[self forceDisconnect];
			}
			else if ([self bufferContainsError:serverResponseBuffer])
			{
				NSString *failureReasonTitle = @"Error!";
				int code = 0;
				BOOL createDirectoryError = NO;
				NSString *localizedErrorString = [NSString stringWithUTF8String:serverResponseBuffer];
				if ([self buffer:serverResponseBuffer containsString:"Error resolving"])
				{
					failureReasonTitle = @"Host Unavailable";
					code = EHOSTUNREACH;
				}
				else if ([self buffer:serverResponseBuffer containsString:"Couldn't create directory"])
				{
					localizedErrorString = @"Create directory operation failed";
					createDirectoryError = YES;
				}
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedErrorString, NSLocalizedDescriptionKey, [sftpWrapperConnection host], @"host", failureReasonTitle, NSLocalizedFailureReasonErrorKey, [NSNumber numberWithBool:createDirectoryError], ConnectionDirectoryExistsKey, nil];
				NSError *error = [NSError errorWithDomain:@"ConnectionErrorDomain" code:code userInfo:userInfo];
				[sftpWrapperConnection connectionError:error];
			}
			else if ([sftpWrapperConnection isBusy])
			{
				if ([sftpWrapperConnection isUploading])
				{
					NSString *localPath = [[sftpWrapperConnection currentUploadInfo] localPath];
					if ([self buffer:serverResponseBuffer containsString:"%"] && [self buffer:serverResponseBuffer containsString:(char *)[localPath UTF8String]])
					{
						[self parseTransferProgressString:(char *)serverResponseBuffer isUploading:YES forWrapperConnection:sftpWrapperConnection];
					}
				}
				else if ([sftpWrapperConnection isDownloading])
				{
					NSString *remotePath = [[sftpWrapperConnection currentDownloadInfo] remotePath];
					if ([self buffer:serverResponseBuffer containsString:"%"] && [self buffer:serverResponseBuffer containsString:(char *)[remotePath UTF8String]])
					{
						[self parseTransferProgressString:(char *)serverResponseBuffer isUploading:NO forWrapperConnection:sftpWrapperConnection];
					}
				}
			}
			else if ([self buffer:serverResponseBuffer containsString:"passphrase for key"])
 			{
				[sftpWrapperConnection passphraseRequested:[NSString stringWithUTF8String:(void *)serverResponseBuffer]];
				passwordWasSent = YES;
			}
			else if ([self buffer:serverResponseBuffer containsString:"Changing owner on"] || [self buffer:serverResponseBuffer containsString:"Changing group on"] || [self buffer:serverResponseBuffer containsString:"Changing mode on"])
			{
				//[sftpWrapperConnection setBusyWithStatusMessage:[NSString stringWithUTF8String:(void *)serverResponseBuffer]];
				wasChanging = YES;
				if ([self buffer:serverResponseBuffer containsString:"Couldn't "])
				{
					NSString *failureReasonTitle = @"Error!";
					int code = 0;
					NSString *localizedErrorString = [NSString stringWithUTF8String:serverResponseBuffer];
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedErrorString, NSLocalizedDescriptionKey, [sftpWrapperConnection host], @"host", failureReasonTitle, NSLocalizedFailureReasonErrorKey, nil];
					NSError *error = [NSError errorWithDomain:@"ConnectionErrorDomain" code:code userInfo:userInfo];
					[sftpWrapperConnection connectionError:error];
				}
			}
			else if ([self unknownHostKeyPromptInBuffer:serverResponseBuffer])
			{
				NSMutableDictionary *hostInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:serverResponseBuffer], @"msg", [self retrieveUnknownHostKeyFromStream:masterFileStream], @"key", nil];
				[sftpWrapperConnection getContinueQueryForUnknownHost:hostInfo];
			}
		}
		if ([self buffer:serverResponseBuffer containsString:"Remote working"])
		{
			char *bufferDump = strdup((char *)serverResponseBuffer);
			char *newline = strrchr(bufferDump, '\r');
			if (newline)
			{
				*newline = '\0';
			}
			char *path = strchr(bufferDump, '/');
			NSString *remotePath = [NSString stringWithBytesOfUnknownEncoding:path length:strlen(path)];
			[sftpWrapperConnection setCurrentRemotePath:remotePath];
			free(bufferDump);
		}
		if ([self hasDirectoryListingFormInBuffer:serverResponseBuffer])
		{
			wasListing = YES;
			[self collectListingFromMaster:master fileStream:masterFileStream forWrapperConnection:sftpWrapperConnection];
			memset(serverResponseBuffer, '\0', strlen(serverResponseBuffer));
			[sftpWrapperConnection didReceiveDirectoryContents:[self remoteObjectList]];
		}
		
		if (serverResponseBuffer[0] != '\0')
		{
			memset(serverResponseBuffer, '\0', strlen(serverResponseBuffer));
		}
		
		[pool release];
		pool = nil;
	}
	
	int status;
	sftppid = wait(&status);
	free(executableArguments);
	[self setCurrentTransferPath:nil];
	connected = NO;
	(void)close(master);
	
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithUTF8String:serverResponseBuffer]];
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"\nsftp task with pid %d ended.\n", sftppid]];
	sftppid = 0;
	[sftpWrapperConnection didDisconnect];
	if (WIFEXITED(status))
	{
		[sftpWrapperConnection addStringToTranscript:@"Normal exit\n"];
	}
	else if (WIFSIGNALED(status))
	{
		[sftpWrapperConnection addStringToTranscript:@"WIFSIGNALED: "];
		[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"signal = %d\n", status]];
	}
	else if (WIFSTOPPED(status))
	{
		[sftpWrapperConnection addStringToTranscript:@"WIFSTOPPED\n"];
	}
}
- ( void )collectListingFromMaster: ( int )theMaster fileStream: ( FILE * )stream
            forWrapperConnection: ( SFTPConnection * )wrapperConnection
{
    char                buf[ MAXPATHLEN * 2 ] = { 0 };
    char                tmp1[ MAXPATHLEN * 2 ], tmp2[ MAXPATHLEN * 2 ];
    int                 len, incomplete_line = 0;
    fd_set              readmask;
    NSMutableDictionary *object = nil;
    NSMutableArray      *items = nil;
    
    /* make sure we're not buffering */
    setvbuf( stream, NULL, _IONBF, 0 );
    
    for ( ;; ) {
        FD_ZERO( &readmask );
        FD_SET( master, &readmask );
        if ( select( master + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
            NSLog( @"select() returned a value less than zero" );
            return;
        }
        
        if ( FD_ISSET( master, &readmask )) {
            if ( fgets(( char * )buf, ( MAXPATHLEN * 2 ), stream ) == NULL ) {
				NSLog(@"Pop out");
                return;
            }

            if ( [ self bufferContainsError: buf ] ) {
				NSString *failureReasonTitle = @"Error!";
				int code = 0;
				NSString *localizedErrorString = [NSString stringWithUTF8String:buf];
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedErrorString, NSLocalizedDescriptionKey, [wrapperConnection host], @"host", failureReasonTitle, NSLocalizedFailureReasonErrorKey, nil];
				NSError *error = [NSError errorWithDomain:@"ConnectionErrorDomain" code:code userInfo:userInfo];
				[wrapperConnection connectionError:error];
                continue;
            }
#ifdef SSH_COM_SUPPORT
            if ( strstr( buf, "<Press any key" ) != NULL ) {
                /* SSH.com's sftp makes you hit a key to get to the prompt. Whee. */
                fdwrite( master, " " );
                continue;
            }
#endif /* SSH_COM_SUPPORT */
            
            /*
             * This is kind of nasty. We don't always get a full line
             * from the server in the 'ls' output, so we have to check
             * if that's the case, flag it, and append the rest of the 
             * text after the next read from the server. Yar!
             */
            len = strlen( buf );
            /* XXX should be modified to handle arbitrary chunks of line */
            if ( strncmp( "sftp>", buf, strlen( "sftp>" )) != 0 &&
                    buf[ len - 1 ] != '\n' ) {
                if ( strlen( buf ) >= sizeof( tmp1 )) {
                    NSLog( @"%s: too long", buf );
                    continue;
                }
                strcpy( tmp1, buf );
                incomplete_line = 1;
                continue;
            }
            if ( incomplete_line ) {
                /* we know this is safe because they're the same buf size */
                strcpy( tmp2, buf );
                memset( buf, '\0', sizeof( buf ));
                
                if ( snprintf( buf, sizeof( buf ), "%s%s", tmp1, tmp2 ) >= sizeof( buf )) {
                    NSLog( @"%s%s: too long", tmp1, tmp2 );
                    continue;
                }
                incomplete_line = 0;
            }
            
            if (( object = [ self remoteObjectFromSFTPLine: buf ] ) != nil ) {
                if ( items == nil ) {
                    items = [[[ NSMutableArray alloc ] init ] autorelease ];
                }
                [ items addObject: object ];
            }
            
            [ wrapperConnection addStringToTranscript: [ NSString stringWithBytesOfUnknownEncoding: buf
                                                length: strlen( buf ) ]];
            if ( strstr( buf, "sftp>" ) != NULL ) {
                memset( buf, '\0', strlen( buf ));
                [ wrapperConnection finishedCommand ];
                [ self setRemoteObjectList: items ];
                return;
            }
        
            memset( buf, '\0', strlen(( char * )buf ));
        }
    }   
}

@end

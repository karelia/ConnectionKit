/*
 Copyright (c) 2005, Greg Hulands <ghulands@framedphotographics.com>
 All rights reserved.
 
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */

/* 
 * Some of this code is based heavily from fugu which is under the same type of license
 * see further down for their copyright information 
 */

#import "SFTPStream.h"
#import "AbstractConnection.h"
#import <errno.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <sys/file.h>
#import <sys/ioctl.h>
#import <sys/param.h>
#import <sys/wait.h>
#import <sys/time.h>
#import <util.h>
#import "InterThreadMessaging.h"
#import "ConnectionThreadManager.h"

enum { START = 200, STOP };

@interface NSArray(CreateArgv)
- ( int )createArgv: ( char *** )argv;
@end

@interface SFTPStream (Private)

- (oneway void)connectToServerWithParams:( NSArray * )params;
- (void)checkBuffers:(id)notused;
- (void)startSFTP;
- (void)stopSFTP;

@end


@implementation SFTPStream

- (id)initWithArguments:(NSArray *)args
{
	[super init];
	
	_args = [args copy];
	_status = NSStreamStatusNotOpen;
	_buffer = [[NSMutableData data] retain];
	_bufferLock = [[NSLock alloc] init];
	_props = [[NSMutableDictionary dictionary] retain];
	
	return self;
}

- (void)dealloc
{
	[_args release];
	[_buffer release]; 
	[_bufferLock release];
	[_delegate release];
	[_props release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark NSStream Methods

- (void)open
{
	
}

- (void)close
{
	_status = NSStreamStatusClosed;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	if (_status != NSStreamStatusNotOpen)
		return;
	
	_status = NSStreamStatusOpening;
	_runThread = YES;
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] startSFTP];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	if (_status == NSStreamStatusNotOpen)
		return;
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] stopSFTP];
	_status = NSStreamStatusNotOpen;
}

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len
{
	_status = NSStreamStatusWriting;
	KTLog(StreamDomain, KTLogDebug, @"<<: %@", [[[NSString alloc] initWithBytes:buffer length:len encoding:NSUTF8StringEncoding] autorelease]);
	
	int wr = write( _master, buffer, len);
	if (wr != len) {
		KTLog(StreamDomain, KTLogError, @"sftp buffer length mismatch. Wrote %d of %d bytes", wr, len);
	}
	_status = NSStreamStatusOpen;
	return wr;
}

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len
{
	[_bufferLock lock];
	_status = NSStreamStatusReading;
	unsigned bufLen = [_buffer length];
	unsigned upperBound = MIN(bufLen, len);
	[_buffer getBytes:buffer range:NSMakeRange(0,upperBound)];
	[_buffer replaceBytesInRange:NSMakeRange(0,upperBound) withBytes:NULL length:0];
	_status = NSStreamStatusOpen;
	[_bufferLock unlock];
	return upperBound;
}

- (void)setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (id)delegate { return _delegate; }

- (NSStreamStatus)streamStatus
{
	return _status;
}

#pragma mark -
#pragma mark Client Process Communication

- (void)startSFTP
{
	_keepChecking = YES;
	[self connectToServerWithParams:_args];
}

- (void)stopSFTP
{
	_keepChecking = NO;
	close(_master);
	_master = 0;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkBuffers:) object:nil];
}

- (oneway void)connectToServerWithParams:( NSArray * )params
{
	if (_sftppid > 0) return;
    struct winsize	win_size = { 24, 512, 0, 0 };
    char		ttyname[ MAXPATHLEN ], **execargs;
    NSArray		*argv = nil, *passedInArgs = [ params copy ];    
    NSString    *sftpBinary = @"/usr/bin/sftp";
	int			rc = 0;
	
    argv = [ NSArray arrayWithObject: sftpBinary ];
    argv = [ argv arrayByAddingObjectsFromArray: passedInArgs ];
    rc = [ argv createArgv: &execargs ];
    [ passedInArgs release ];
	    
    switch (( _sftppid = forkpty( &_master, ttyname, NULL, &win_size ))) 
	{
		case 0:
		{
			NSDictionary *env = [[NSProcessInfo processInfo] environment];
			char **newEnv = (char **)malloc(sizeof(char *) * ([[env allKeys] count] + 1));
			memset(newEnv,0,[[env allKeys] count] + 1);
			NSArray *keys = [env allKeys];
			NSString *key;
			int i;
			//NSLog(@"%d env vars", [keys count]);
			for (i = 0; i < [keys count]; i++)
			{
				key = [keys objectAtIndex:i];
				newEnv[i] = (char *)[[NSString stringWithFormat:@"%@=%@", key, [env objectForKey:key]] UTF8String];
			}
			execve( execargs[ 0 ], ( char ** )execargs,  newEnv);
			KTLog(StreamDomain, KTLogFatal, @"Couldn't launch sftp: %s", strerror( errno ));
			return;					/* shouldn't get here */			
		}
						
		case -1:
			KTLog(StreamDomain, KTLogError, @"forkpty failed: %s", strerror( errno ));
			return;
			
		default:
			break;
    }
    
    if ( fcntl( _master, F_SETFL, O_NONBLOCK ) < 0 ) 
	{	/* prevent master from blocking */
        KTLog(StreamDomain, KTLogError, @"fcntl non-block failed: %s", strerror( errno ));
    }

    if (( _mf = fdopen( _master, "r+" )) == NULL ) {
        KTLog(StreamDomain, KTLogError, @"failed to open file stream with fdopen: %s", strerror( errno ));
        return;
    }
    setvbuf( _mf, NULL, _IONBF, 0 );
	_keepChecking = YES;

    [self checkBuffers:nil];
}

- (void)checkBuffers:(id)notused 
{
	char *buf[ MAXPATHLEN ];
	fd_set readmask;
	FD_ZERO(&readmask);
	FD_SET(_master, &readmask);
	struct timeval timeout;
	timeout.tv_sec = 3;
	timeout.tv_usec = 0;
	
	switch(select(_master + 1, &readmask, NULL, NULL, &timeout)) 
	{
		case -1:
		{
			KTLog(StreamDomain, KTLogError, @"select: %s", strerror( errno ));
			break;
		}
		case 0:	
		{
			/* timeout */
			if (_keepChecking == YES)
			{
				[self performSelector:@selector(checkBuffers:)
						   withObject:nil
							 inThread:[NSThread currentThread]];
			}
			return;
		}	
		default:
			break;
	}
	
	if (!_keepChecking) return;
	
	if (FD_ISSET( _master, &readmask )) 
	{
		size_t amount;
		amount = read(fileno(_mf), buf, MAXPATHLEN);
		
		if (amount > 0) 
		{
			[_bufferLock lock];
			[_buffer appendBytes:buf length:amount];
			[_bufferLock unlock];
			
			if ([self delegate])
			{
				[_delegate stream:self handleEvent:NSStreamEventHasBytesAvailable];
			}
		}
	}
	
	// give time to the runloop to process port messages
	if (_keepChecking == YES)
	{
		[self performSelector:@selector(checkBuffers:)
				   withObject:nil
					 inThread:[NSThread currentThread]];
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"SFTPStream - sftp process id = %d", _sftppid];
}

- (NSError *)streamError
{
	return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
	[_props setObject:property forKey:key];
	return YES;
}

- (id)propertyForKey:(NSString *)key
{
	return [_props objectForKey:key];
}


@end


// The following is code is from Fugu
/*
Copyright (c) 2005 Regents of The University of Michigan.
All Rights Reserved.

Permission to use, copy, modify, and distribute this software and
its documentation for any purpose and without fee is hereby granted,
provided that the above copyright notice appears in all copies and
that both that copyright notice and this permission notice appear
in supporting documentation, and that the name of The University
of Michigan not be used in advertising or publicity pertaining to
distribution of the software without specific, written prior
permission. This software is supplied as is without expressed or
implied warranties of any kind.

Research Systems Unix Group
The University of Michigan
c/o Wesley Craig
4251 Plymouth Road B1F2, #2600
Ann Arbor, MI 48105-2785

http://rsug.itd.umich.edu/software/fugu
fugu@umich.edu
*/

@implementation NSArray(CreateArgv)

- ( int )createArgv: ( char *** )argv
{
    char			**av;
    int				i, ac = 0, actotal;
    
    if ( self == nil || [ self count ] == 0 ) {
        *argv = NULL;
        return( 0 );
    }
    
    actotal = [ self count ];
    
    if (( av = ( char ** )malloc( sizeof( char * ) * actotal )) == NULL ) {
        NSLog( @"malloc: %s", strerror( errno ));
        exit( 2 );
    }
    
    for ( i = 0; i < [ self count ]; i++ ) {
        av[ i ] = ( char * )[[ self objectAtIndex: i ] UTF8String ];
        ac++;
        
        if ( ac >= actotal ) {
            if (( av = ( char ** )realloc( av, sizeof( char * ) * ( actotal + 10 ))) == NULL ) {
                NSLog( @"realloc: %s", strerror( errno ));
                exit( 2 );
            }
            actotal += 10;
        }
    }
    
    if ( ac >= actotal ) {
        if (( av = ( char ** )realloc( av, sizeof( char * ) * ( actotal + 10 ))) == NULL ) {
            NSLog( @"realloc: %s", strerror( errno ));
            exit( 2 );
        }
        actotal += 10;
    }
    
    av[ i ] = NULL;
    *argv = av;
    
    return( ac );
}

@end
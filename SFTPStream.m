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

extern char	**environ;

enum { START = 200, STOP };

@interface NSArray(CreateArgv)
- ( int )createArgv: ( char *** )argv;
@end

@interface SFTPStream (Private)

- (void)sendPortMessage:(int)msg;
- (oneway void)connectToServerWithParams:( NSArray * )params;

@end


@implementation SFTPStream

- (id)initWithArguments:(NSArray *)args
{
	[super init];
	
	_args = [args copy];
	_status = NSStreamStatusNotOpen;
	_buffer = [[NSMutableData data] retain];
	_bufferLock = [[NSLock alloc] init];
	_forwarder = [[RunLoopForwarder alloc] init];
	_props = [[NSMutableDictionary dictionary] retain];
	
	return self;
}

- (void)dealloc
{
	[_port setDelegate:nil];
	[_port release];
	[_args release];
	[_buffer release];
	[_bufferLock release];
	[_forwarder release];
	[_props release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark NSStream Methods

- (void)open
{
	[self sendPortMessage:START];
}

- (void)close
{
	[_port setDelegate:nil];
	[_port release];
	_port = nil;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	if (_status != NSStreamStatusNotOpen)
		return;
	
	_status = NSStreamStatusOpening;
	_port = [[NSPort port] retain];
	[_port setDelegate:self];
	[NSThread detachNewThreadSelector:@selector(runBackgroundThread:)
							 toTarget:self
						   withObject:nil];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[self sendPortMessage:STOP];
}

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len
{
	_status = NSStreamStatusWriting;
	//if ([AbstractConnection logStateChanges])
		//NSLog(@"sftp_stream <<: %@", [[[NSString alloc] initWithBytes:buffer length:len encoding:NSUTF8StringEncoding] autorelease]);
	
	int wr = write( _master, buffer, len);
	if (wr != len) {
		NSLog(@"sftp buffer length mismatch. Wrote %d of %d bytes", wr, len);
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
	[_forwarder setDelegate:delegate];	// note that its delegate it not retained.
}

- (id)delegate { return _delegate; }

- (NSStreamStatus)streamStatus
{
	return _status;
}

#pragma mark -
#pragma mark Client Process Communication

- (void)runBackgroundThread:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
	// But then again, we can't remove the thread, so it really doesn't mean much.
	[NSThread prepareForInterThreadMessages];
	[[NSRunLoop currentRunLoop] addPort:_port forMode:(NSString *)kCFRunLoopCommonModes];
	
	[[NSRunLoop currentRunLoop] run];
	
	[pool release];
}

/*!	Send a message from the main thread to the port, to communicate with the background thread.
*/
- (void)sendPortMessage:(int)aMessage
{
	if (nil != _port)
	{
		NSPortMessage *message
		= [[NSPortMessage alloc] initWithSendPort:_port
									  receivePort:_port components:nil];
		[message setMsgid:aMessage];
		BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];
		if (!sent)
		{
			NSLog(@"SFTPStream failed to send port message: %d", aMessage);
		}
		[message release];
	}
}

/*" NSPortDelegate method gets called in the background thread.
"*/
- (void)handlePortMessage:(NSPortMessage *)portMessage
{
	
	switch ([portMessage msgid]) {
		case START:
			[self connectToServerWithParams:_args];
			break;
		case STOP:
			[[NSRunLoop currentRunLoop] removePort:_port forMode:(NSString *)kCFRunLoopCommonModes];
			break;
	}
}

- (oneway void)connectToServerWithParams:( NSArray * )params
{
	if (_sftppid > 0) return;
	fd_set		readmask;
    struct winsize	win_size = { 24, 512, 0, 0 };
    FILE		*mf = NULL;
    char		ttyname[ MAXPATHLEN ], **execargs;
    char		buf[ MAXPATHLEN * 2 ];
    NSArray		*argv = nil, *passedInArgs = [ params copy ];    
    NSString    *sftpBinary = @"/usr/bin/sftp";
	int			rc = 0;
	
    argv = [ NSArray arrayWithObject: sftpBinary ];
    argv = [ argv arrayByAddingObjectsFromArray: passedInArgs ];
    rc = [ argv createArgv: &execargs ];
    [ passedInArgs release ];
	    
    switch (( _sftppid = forkpty( &_master, ttyname, NULL, &win_size ))) {
		case 0:
			execve( execargs[ 0 ], ( char ** )execargs, environ );
			NSLog( @"Couldn't launch sftp: %s", strerror( errno ));
			_exit( 2 );						/* shouldn't get here */
			
		case -1:
			NSLog( @"forkpty failed: %s", strerror( errno ));
			exit( 2 );
			
		default:
			break;
    }
    
    if ( fcntl( _master, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        NSLog( @"fcntl non-block failed: %s", strerror( errno ));
    }

    if (( mf = fdopen( _master, "r+" )) == NULL ) {
        NSLog( @"failed to open file stream with fdopen: %s", strerror( errno ));
        return;
    }
    setvbuf( mf, NULL, _IONBF, 0 );

    for ( ;; ) {
        NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
        FD_ZERO( &readmask );
        FD_SET( _master, &readmask );
        
        switch( select( _master + 1, &readmask, NULL, NULL, NULL )) {
			case -1:
				NSLog( @"select: %s", strerror( errno ));
				break;
				
			case 0:	/* timeout */
				NSLog(@"sftp timed out");
				continue;
					
				default:
					break;
        }
        
        if ( FD_ISSET( _master, &readmask )) {
			size_t amount;
			amount = read(fileno(mf), buf, MAXPATHLEN);
			
			if (amount > 0) {
				//if ([AbstractConnection logStateChanges])
					//NSLog(@"sftp_stream >> %d: %@",amount, [[[NSString alloc] initWithBytes:buf length:amount encoding:NSUTF8StringEncoding] autorelease]);
				
				[_bufferLock lock];
				[_buffer appendBytes:buf length:amount];
				[_bufferLock unlock];
				
				if ([self delegate])
					[_forwarder stream:self handleEvent:NSStreamEventHasBytesAvailable];
			} else {
				//NSLog(@"read 0 bytes, shutting down");
				int status;
				_sftppid = wait( &status );
				_status = NSStreamStatusClosed;
				close( _master );
				free( execargs );
				
				[_forwarder stream:self handleEvent:NSStreamEventEndEncountered];
				break;
			}
		}
		//[NSThread sleepUntilDate:[NSDate distantPast]];
		[p release];
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
//
//  CKTelnetConnection.m
//  Connection
//
//  Created by Mike on 20/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKTelnetConnection.h"


@interface CKTelnetConnection ()
- (id <CKTelnetConnectionDelegate>)delegate;
@end


#pragma mark -


@implementation CKTelnetConnection

- (id)initWithURL:(NSURL *)URL delegate:(id <CKTelnetConnectionDelegate>)delegate;
{
    if ([URL scheme] && [[URL scheme] isEqualToString:@"telnet"] &&
        [URL host] && ![[URL host] isEqualToString:@""])
    {
        self = [self initWithHost:[URL host] port:[[URL port] intValue] delegate:delegate];
        return self;
    }
    else
    {
        [self release];
        return nil;
    }
}

- (id)initWithHost:(NSString *)hostName 
              port:(NSInteger)port
          delegate:(id <CKTelnetConnectionDelegate>)delegate
{
    if (self = [super init])
    {
        _delegate = delegate;
        
        // Standard telnet port is 23
        if (!port) port = 23;
        
        // The NSStream-equivalent is not in the iPhone SDK
        CFStreamCreatePairWithSocketToHost(NULL,
                                           (CFStringRef)hostName,
                                           port,
                                           &(CFReadStreamRef)_readStream,
                                           &(CFWriteStreamRef)_writeStream);
        
        // Properties only need to be set for one stream
        [_readStream setDelegate:self];
        [_readStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [_readStream open];
    }
    
    return self;
}

- (id <CKTelnetConnectionDelegate>)delegate { return _delegate; }

- (void)close
{
    [_readStream close];
    [_writeStream close];
    [_readStream release];  _readStream = nil;
    [_writeStream release]; _writeStream = nil;
}

- (BOOL)sendLine:(NSString *)line
{
    BOOL result = NO;
    
    NSData *data = [line dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    if (data)
    {
        NSInteger writeResult = [_writeStream write:[data bytes] maxLength:[data length]];
        result = (writeResult == [data length]);
        
        // Also send the failure callback if needed
        if (writeResult == -1)
        {
            [[self delegate] connection:self didFailWithError:[_writeStream streamError]];
        }
    }
    
    return result;
}

@end

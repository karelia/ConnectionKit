//
//  CKTelnetConnection.h
//  Connection
//
//  Created by Mike on 20/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@protocol CKTelnetConnectionDelegate;


@interface CKTelnetConnection : NSObject
{

}

// The URL should follow RFC 4248
- (id)initWithURL:(NSURL *)URL delegate:(id <CKTelnetConnectionDelegate>)delegate;

- (id)initWithHost:(NSString *)hostName 
              port:(NSInteger)port
          delegate:(id <CKTelnetConnectionDelegate>)delegate;

// Returns NO if the string could not be encoded
- (BOOL)sendLine:(NSString *)line;
- (void)close;

@end


@protocol CKTelnetConnectionDelegate
- (void)connection:(CKTelnetConnection *)connection didReceiveLine:(NSString *)line;
- (void)connection:(CKTelnetConnection *)connection didFailWithError:(NSError *)error;
@end
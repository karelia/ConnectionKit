//
//  CKFileOperation.m
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_FileOperation.h"


@implementation CK_FileOperation

- (id)initWithIdentifier:(id <NSObject>)identifier
                 request:(CKFileRequest *)request
              connection:(CKFileTransferConnection *)connection;
{
    [self init];
    
    _identifier = (identifier) ? [identifier retain] : [[NSObject alloc] init];
    _request = [request copy];
    _connection = connection;
    
    return self;
}

- (void)dealloc
{
    [_identifier release];
    [_request release];
    
    [super dealloc];
}

@synthesize identifier = _identifier;
@synthesize request = _request;
@synthesize connection = _connection;

// Inform the connection it's time to start the operation
- (void)main
{
    [[self connection] CK_operationDidBegin:self];
}

@end

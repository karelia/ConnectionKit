//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CK2FileManagerWithTestSupport.h"
#import "CK2FileOperationWithTestSupport.h"

#import <CURLHandle/CURLHandle+TestingSupport.h>

@implementation CK2FileManagerWithTestSupport

@synthesize dontShareConnections = _dontShareConnections;
@synthesize multi = _multi;

- (void)dealloc
{
    [CURLHandle cleanupStandaloneMulti:_multi];
    [_multi release];

    [super dealloc];
}

- (Class)classForOperation
{
    return [CK2FileOperationWithTestSupport class];
}

- (CURLMulti*)multi
{
    if (_dontShareConnections && !_multi)
    {
        _multi = [[CURLHandle standaloneMultiForTestPurposes] retain];
    }

    return _dontShareConnections ? _multi : nil;
}

@end

@implementation NSURLRequest(CK2FileManagerDebugging)

- (CURLMulti*)ck2_multi
{
    return [NSURLProtocol propertyForKey:@"ck2_multi" inRequest:self];
}

@end
@implementation NSMutableURLRequest(CK2FileManagerDebugging)

- (void)ck2_setMulti:(CURLMulti*)multi
{
    [NSURLProtocol setProperty:multi forKey:@"ck2_multi" inRequest:self];
}


@end


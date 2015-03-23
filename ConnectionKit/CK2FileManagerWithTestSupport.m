//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CK2FileManagerWithTestSupport.h"
#import "CK2FileOperationWithTestSupport.h"

#import <CURLHandle/CURLHandle.h>


@interface CURLTransfer (Testing)
+ (void)cleanupStandaloneMulti:(CURLTransferStack *)multi;
+ (CURLTransferStack *)standaloneMultiForTestPurposes;
@end


@implementation CK2FileManagerWithTestSupport

@synthesize dontShareConnections = _dontShareConnections;
@synthesize multi = _multi;

- (void)dealloc
{
    [CURLTransfer cleanupStandaloneMulti:_multi];
    [_multi release];

    [super dealloc];
}

- (Class)classForOperation
{
    return [CK2FileOperationWithTestSupport class];
}

- (CURLTransferStack*)multi
{
    if (_dontShareConnections && !_multi)
    {
        _multi = [[CURLTransfer standaloneMultiForTestPurposes] retain];
    }

    return _dontShareConnections ? _multi : nil;
}

@end

@implementation NSURLRequest(CK2FileManagerDebugging)

- (CURLTransferStack*)ck2_multi
{
    return [NSURLProtocol propertyForKey:@"ck2_multi" inRequest:self];
}

@end
@implementation NSMutableURLRequest(CK2FileManagerDebugging)

- (void)ck2_setMulti:(CURLTransferStack*)multi
{
    [NSURLProtocol setProperty:multi forKey:@"ck2_multi" inRequest:self];
}


@end


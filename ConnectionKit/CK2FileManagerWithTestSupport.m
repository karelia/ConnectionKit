// Additional API for debugging / unit testing only.

#import "CK2FileManagerWithTestSupport.h"
#import <CURLHandle/CURLHandle.h>

@class CURLMulti;

@interface CK2FileManagerWithTestSupport()
/**
 Set this property to force CURL based protocols use an alternative CURLMulti instead of the default one.
 */

@property (strong, readonly, nonatomic) CURLMulti* multi;

@end

@implementation CK2FileManagerWithTestSupport

@synthesize dontShareConnections = _dontShareConnections;
@synthesize multi = _multi;

- (void)dealloc
{
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

@implementation CK2FileOperationWithTestSupport

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
    CK2FileManagerWithTestSupport* manager = (CK2FileManagerWithTestSupport*)_manager;
    if (manager.dontShareConnections)
    {
        [request ck2_setMulti:manager.multi];
    }

    return request;
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


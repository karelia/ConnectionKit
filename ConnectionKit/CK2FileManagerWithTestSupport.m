// Additional API for debugging / unit testing only.

#import "CK2FileManagerWithTestSupport.h"

@class CURLMulti;

@implementation CK2FileManagerWithTestSupport

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

@end

@implementation CK2FileOperationWithTestSupport

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
    CURLMulti* multi = [(CK2FileManagerWithTestSupport*)_manager multi];
    [request ck2_setMulti:multi];

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


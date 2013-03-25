
#import "CK2FileManager.h"
#import "CK2FileOperation.h"

@class CURLMulti;

/**
 CK2FileManager with some additional API for test purposes.
 */

@interface CK2FileManagerWithTestSupport : CK2FileManager
{
    CURLMulti* _multi;
}

/**
 Set this property to force CURL based protocols use an alternative CURLMulti instead of the default one.
 */

@property (strong, nonatomic) CURLMulti* multi;

@end

@interface CK2FileOperationWithTestSupport : CK2FileOperation
@end

@interface NSURLRequest(CK2FileManagerDebugging)
- (CURLMulti*)ck2_multi;
@end

@interface NSMutableURLRequest(CK2FileManagerDebugging)
- (void)ck2_setMulti:(CURLMulti*)multi;
@end


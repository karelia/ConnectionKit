//
//  CK2RemoteURL.m
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import "CK2RemoteURL.h"

#import "CK2FileManager.h"


@implementation CK2RemoteURL

- (void)dealloc;
{
    [_temporaryResourceValues release];
    [super dealloc];
}

+ (CK2RemoteURL*)URLWithURL:(NSURL*)url
{
    CK2RemoteURL* result = [[CK2RemoteURL alloc] initWithString:[url relativeString] relativeToURL:[url baseURL]];

    return [result autorelease];
}

#pragma mark Getting and Setting File System Resource Properties

- (BOOL)getResourceValue:(out id *)value forKey:(NSString *)key error:(out NSError **)error;
{
    *value = [_temporaryResourceValues objectForKey:key];
    if (*value == nil)
    {
        // A few keys we generate on-demand pretty much by guessing since the server isn't up to providing that sort of info
        if ([key isEqualToString:NSURLHasHiddenExtensionKey])
        {
            *value = [NSNumber numberWithBool:NO];
            return YES;
        }
        else if ([key isEqualToString:NSURLLocalizedNameKey])
        {
            *value = [self lastPathComponent];
            return YES;
        }
        
        // Have to define NSURLPathKey as a macro for older releases:
#if (!defined MAC_OS_X_VERSION_10_8) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8
#define NSURLPathKey @"_NSURLPathKey"
#endif
        else if ([key isEqualToString:NSURLPathKey])
        {
            *value = [CK2FileManager pathOfURL:self];
            return YES;
        }
#undef NSURLPathKey
        
        else
        {
            return [super getResourceValue:value forKey:key error:error];
        }
    }
    else if (*value == [NSNull null])
    {
        *value = nil;
    }
    
    return YES;
}

- (NSDictionary *)resourceValuesForKeys:(NSArray *)keys error:(NSError **)error;
{
    return [super resourceValuesForKeys:keys error:error];
}

- (void)setTemporaryResourceValue:(id)value forKey:(NSString *)key;
{
    if (!_temporaryResourceValues) _temporaryResourceValues = [[NSMutableDictionary alloc] initWithCapacity:1];
    if (!value) value = [NSNull null];
    [_temporaryResourceValues setObject:value forKey:key];
}

@end

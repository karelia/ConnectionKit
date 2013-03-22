//
//  CK2RemoteURL.m
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import "CK2RemoteURL.h"

#import "CK2FileManager.h"


@interface NSURL (CK2RemoteURL)
- (CK2RemoteURL *)ck2_remoteURL;
@end


@implementation CK2RemoteURL

- (void)dealloc;
{
    [_temporaryResourceValues release];
    [super dealloc];
}

+ (CK2RemoteURL*)URLWithURL:(NSURL*)url { return [url ck2_remoteURL]; }

- (CK2RemoteURL *)ck2_remoteURL; { return self; }

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
        
        else if ([key isEqualToString:NSURLIsPackageKey])
        {
            NSString        *extension;
            
            extension = [self pathExtension];
            
            if ([extension length] > 0)
            {
                if ([extension isEqual:@"app"])
                {
                    return YES;
                }
                else
                {
                    OSStatus        status;
                    
                    status = LSGetApplicationForInfo(kLSUnknownType, kLSUnknownCreator, (CFStringRef)extension, kLSRolesAll, NULL, NULL);
                    
                    if (status == kLSApplicationNotFoundErr)
                    {
                        return NO;
                    }
                    else if (status != noErr)
                    {
                        NSLog(@"Error getting app info for extension for URL %@: %s", [self absoluteString], GetMacOSStatusCommentString(status));
                    }
                    else
                    {
                        return YES;
                    }
                }
            }
            
            return NO;
        }
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


@implementation NSURL (CK2RemoteURL)

- (CK2RemoteURL *)ck2_remoteURL;
{
    CK2RemoteURL *result = [[CK2RemoteURL alloc] initWithString:self.relativeString relativeToURL:self.baseURL];
    return [result autorelease];
}

@end
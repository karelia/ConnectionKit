//
//  CKRemoteURL.m
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import "CKRemoteURL.h"

@implementation CKRemoteURL

- (void)dealloc;
{
    [_temporaryResourceValues release];
    [super dealloc];
}

#pragma mark Getting and Setting File System Resource Properties

- (BOOL)getResourceValue:(out id *)value forKey:(NSString *)key error:(out NSError **)error;
{
    *value = [_temporaryResourceValues objectForKey:key];
    if (*value == nil)
    {
        return [super getResourceValue:value forKey:key error:error];
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

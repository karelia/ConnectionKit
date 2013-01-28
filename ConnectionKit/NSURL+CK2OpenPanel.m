//
//  NSURL+CKRemote.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/15/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or other
// materials provided with the distribution.
//
// Neither the name of Karelia Software nor the names of its contributors may be used to
// endorse or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
// SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
// WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "NSURL+CK2OpenPanel.h"
#import "CK2FileManager.h"
#import "NSImage+CK2OpenPanel.h"
#import <dispatch/dispatch.h>

@interface CK2PlaceholderURL : NSURL
@end


@implementation NSURL (CK2OpenPanel)

+ (NSURL *)ck2_loadingURL
{
    return [[[CK2PlaceholderURL alloc] initWithString:@"Loading…"] autorelease];
}

+ (NSURL *)ck2_errorURL
{
    return [[[CK2PlaceholderURL alloc] initWithString:@"Error"] autorelease];
}

+ (NSComparator)ck2_displayComparator
{
    return [[^NSComparisonResult(id obj1, id obj2)
             {
                  return [[obj1 lastPathComponent] caseInsensitiveCompare:[obj2 lastPathComponent]];
             } copy] autorelease];
}


- (BOOL)ck2_isPlaceholder
{
    return NO;
}

- (NSString *)ck2_displayName
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLLocalizedNameKey error:&error])
    {
        return value;
    }
    else
    {
        NSLog(@"Error getting name for URL %@: %@", [self absoluteString], error);
    }
    return @"";
}

- (NSImage *)ck2_icon
{
    if ([self isFileURL])
    {
        id          value;
        NSError     *error;
        
        if ([self getResourceValue:&value forKey:NSURLEffectiveIconKey error:&error])
        {
            return value;
        }
        else
        {
            NSLog(@"Error getting icon for URL %@: %@", [self absoluteString], error);
        }
    }
    else
    {
        NSURL       *actualURL;
        NSImage     *image;
        NSString    *type;
        
        actualURL = [self ck2_destinationURL];
        
        if ([actualURL ck2_canHazChildren])
        {
            image = [NSImage imageNamed:NSImageNameFolder];
        }
        else
        {
            type = [actualURL pathExtension];
        
            if ([type isEqual:@"app"])
            {
                type = NSFileTypeForHFSTypeCode(kGenericApplicationIcon);
            }
            image = [[NSWorkspace sharedWorkspace] iconForFileType:type];
        }
        
        if (![self isEqual:actualURL])
        {
            image = [image ck2_imageWithBadgeImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kAliasBadgeIcon)]];
        }
        
        return image;
    }
    return nil;
}

- (NSDate *)ck2_dateModified
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLContentModificationDateKey error:&error])
    {
        return value;
    }
    else
    {
        NSLog(@"Error getting date modified for URL %@: %@", [self absoluteString], error);
    }
    return nil;
}

- (NSString *)ck2_kind
{
    if ([self isFileURL])
    {
        id          value;
        NSError     *error;
        
        if ([self getResourceValue:&value forKey:NSURLLocalizedTypeDescriptionKey error:&error])
        {
            return value;
        }
        else
        {
            NSLog(@"Error getting kind for URL %@: %@", [self absoluteString], error);
        }
    }
    else
    {
        NSString        *type;
        OSStatus        status;
        CFStringRef     kindString;

        if ([self ck2_canHazChildren])
        {
            return @"Folder";
        }
        else if ([self ck2_isSymbolicLink])
        {
            return @"Alias";
        }

        type = [self pathExtension];
        status = LSCopyKindStringForTypeInfo(kLSUnknownType, kLSUnknownCreator, (CFStringRef)type, &kindString);
        
        if (status == noErr)
        {
            return [(NSString *)kindString autorelease];
        }
        else
        {
            NSLog(@"Error getting kind for URL %@: %s", [self absoluteString], GetMacOSStatusCommentString(status));
        }
    }
    return @"";
}

- (NSNumber *)ck2_size
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLFileSizeKey error:&error])
    {
        return value;
    }
    else
    {
        NSLog(@"Error getting size for URL %@: %@", [self absoluteString], error);
    }
    return nil;
}

- (BOOL)ck2_isDirectory
{
    id          value;
    NSError     *error;
    NSURL       *actualURL;
    
    actualURL = [self ck2_destinationURL];
    
    if ([actualURL getResourceValue:&value forKey:NSURLIsDirectoryKey error:&error])
    {
        if (value == nil)
        {
            // Info is not filled out. We will default to YES to force a directory listing
            return YES;
        }
        
        return [value boolValue];
    }
    else
    {
        NSLog(@"Error getting isDirectory for URL %@: %@", [self absoluteString], error);
    }
    return NO;
}

- (BOOL)ck2_isPackage
{
    if ([self isFileURL])
    {
        id          value;
        NSError     *error;
        
        if ([self getResourceValue:&value forKey:NSURLIsPackageKey error:&error])
        {
            return [value boolValue];
        }
        else
        {
            NSLog(@"Error getting isPackage for URL %@: %@", [self absoluteString], error);
        }
        return NO;
    }
    else
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
    }
    return NO;
}

- (BOOL)ck2_isSymbolicLink
{
    id      value;
    NSError *error;
    
    error = nil;
    if ([self getResourceValue:&value forKey:NSURLIsSymbolicLinkKey error:&error])
    {
        return [value boolValue];
    }
    else
    {
        NSLog(@"Error determining if symbolic link for url %@: %@", self, error);
    }
    return NO;
}

- (BOOL)ck2_canHazChildren
{
    return [self ck2_isDirectory] && ![self ck2_isPackage];
}

- (NSURL *)ck2_destinationURL
{
    id      value;
    NSError *error;

    error = nil;
    
    // Not sure if CK2URLSymbolicLinkDestinationKey implies this but doing it just to be safe
    if ([self ck2_isSymbolicLink])
    {
        if ([self getResourceValue:&value forKey:CK2URLSymbolicLinkDestinationKey error:&error])
        {
            return value;
        }
        else
        {
            NSLog(@"Error getting destination link for url %@: %@", self, error);
        }
    }

    return self;
}

- (NSURL *)ck2_root
{
    return [[CK2FileManager URLWithPath:@"/" relativeToURL:self] absoluteURL];
}

- (BOOL)ck2_isAncestorOfURL:(NSURL *)url
{
    NSArray     *components, *otherComponents;
    NSUInteger  i, count, otherCount;
    
    components = [self pathComponents];
    count = [components count];
    otherComponents = [url pathComponents];
    otherCount = [otherComponents count];
    
    if (otherCount >= count)
    {
        for (i = 0; i < count; i++)
        {
            if (![[components objectAtIndex:i] isEqual:[otherComponents objectAtIndex:i]])
            {
                return NO;
            }
        }
        return YES;
    }
    return NO;
}

- (NSString *)ck2_pathRelativeToURL:(NSURL *)url
{
    NSArray             *components, *otherComponents;
    NSUInteger          i, count;
    NSMutableString     *path;
    
    components = [self pathComponents];
    count = [components count];
    otherComponents = [url pathComponents];
    
    for (i = 0; i < count; i++)
    {
        if (![[components objectAtIndex:i] isEqual:[otherComponents objectAtIndex:i]])
        {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Cannot enumerate from %@ to %@. Former is not an ancestor of the latter.", [self absoluteString], [url absoluteString]] userInfo:nil];
        }
    }
    
    path = [NSMutableString string];
    count = [otherComponents count];
    for (i = [components count]; (i < count); i++)
    {
        [path appendFormat:@"/%@", [otherComponents objectAtIndex:i]];
    }

    return path;
}

- (void)ck2_enumerateToURL:(NSURL *)url usingBlock:(void (^)(NSURL *url, BOOL *stop))block
{
    NSURL               *tempURL;
    NSArray             *components, *otherComponents;
    NSUInteger          i, count;
    
    if (block != NULL)
    {
        BOOL    stop;
        
        components = [self pathComponents];
        otherComponents = [url pathComponents];
        count = [components count];
        
        for (i = 0; i < count; i++)
        {
            if (![[components objectAtIndex:i] isEqual:[otherComponents objectAtIndex:i]])
            {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Cannot enumerate from %@ to %@. Former is not an ancestor of the latter.", [self absoluteString], [url absoluteString]] userInfo:nil];
            }
        }
        
        tempURL = self;
        
        stop = NO;
        count = [otherComponents count];
        
        block(tempURL, &stop);
        
        if (!stop)
        {
            for (i = [components count]; (i < count) && !stop; i++)
            {
                tempURL = [tempURL URLByAppendingPathComponent:[otherComponents objectAtIndex:i] isDirectory:YES];
                
                block(tempURL, &stop);
            }
        }
    }
}


- (void)ck2_enumerateFromRoot:(void (^)(NSURL *url, BOOL *stop))block
{
    NSURL               *tempURL;
    NSArray             *targetComponents;
    NSUInteger          i, count;
    
    if (block != NULL)
    {
        BOOL    stop;
        
        targetComponents = [self pathComponents];
        count = [targetComponents count];
        
        tempURL = [self ck2_root];
        
        stop = NO;
        
        block(tempURL, &stop);
        
        if (!stop)
        {
            for (i = 1; (i < count) && !stop; i++)
            {
                tempURL = [tempURL URLByAppendingPathComponent:[targetComponents objectAtIndex:i] isDirectory:YES];
            
                block(tempURL, &stop);
            }
        }
    }
}

- (NSURL *)ck2_URLByDeletingTrailingSlash
{
    NSString    *path;
    NSUInteger  startIndex, endIndex;
    
    path = [self path];
    startIndex = 0;
    endIndex = [path length];
    if ([path hasPrefix:@"//"])
    {
        startIndex++;
    }
    if ([path hasSuffix:@"/"])
    {
        endIndex--;
    }
    path = [path substringWithRange:NSMakeRange(startIndex, endIndex - startIndex)];
    
    // Quite the rigamarole just to get an URL without the trailing slash
    return [[CK2FileManager URLWithPath:path relativeToURL:[self ck2_root]] absoluteURL];
}

@end


@implementation CK2PlaceholderURL

- (BOOL)ck2_isPlaceholder
{
    return YES;
}

- (NSString *)ck2_displayName
{
    return [[self absoluteString] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

- (NSImage *)ck2_icon
{
    return nil;
}

- (NSDate *)ck2_dateModified
{
    return nil;
}

- (NSString *)ck2_kind
{
    return @"";
}

- (NSString *)sizeString
{
    return @"";
}

- (BOOL)ck2_isDirectory
{
    return NO;
}

- (BOOL)ck2_canHazChildren
{
    return NO;
}
- (BOOL)isEqual:(id)object
{
    return self == object;
}

- (NSUInteger)hash
{
    return (NSUInteger)self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

@end



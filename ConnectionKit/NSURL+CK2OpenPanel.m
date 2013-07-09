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
    return [[[CK2PlaceholderURL alloc] initWithString:[NSLocalizedStringFromTableInBundle(@"Loading…", nil, [NSBundle bundleForClass:[self class]], @"Loading placeholder")stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] autorelease];
}

+ (NSURL *)ck2_errorURL
{
    return [[[CK2PlaceholderURL alloc] initWithString:[NSLocalizedStringFromTableInBundle(@"Error", nil, [NSBundle bundleForClass:[self class]], @"Error placedholer")stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] autorelease];
}

+ (NSURL *)ck2_errorURLWithMessage:(NSString *)message
{
    return [[[CK2PlaceholderURL alloc] initWithString:[message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] autorelease];
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
    id          value;
    NSError     *error;
        
    if ([self getResourceValue:&value forKey:NSURLEffectiveIconKey error:&error])
    {
        NSImage     *image;
        NSURL       *actualURL;

        image = nil;
        actualURL = [self ck2_destinationURL];
        
        if (value == nil)
        {
            // Value may not be set (i.e. we created this URL instead of having it returned from CK2FileManager). We
            // provide some default images in this case.
            if ([actualURL ck2_isDirectory] && ![actualURL ck2_isPackage])
            {
                image = [NSImage imageNamed:NSImageNameFolder];
            }
            else
            {
                image = [[NSWorkspace sharedWorkspace] iconForFileType: NSFileTypeForHFSTypeCode(kGenericDocumentIcon)];
            }
        }
        else if ([value isKindOfClass:[NSImage class]])
        {
            image = value;
        }
        else
        {
            NSLog(@"Received unexpected type for icon: %@", [value class]);
            return nil;
        }
        
        if (![self isEqual:actualURL])
        {
            image = [image ck2_imageWithBadgeImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kAliasBadgeIcon)]];
        }
        
        return image;
    }
    else
    {
        NSLog(@"Error getting icon for URL %@: %@", [self absoluteString], error);
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

        if ([self ck2_isDirectory] && ![self ck2_isPackage])
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

- (BOOL)ck2_isHidden
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLIsHiddenKey error:&error])
    {
        return [value boolValue];
    }
    else
    {
        NSLog(@"Error getting isHidden for URL %@: %@", [self absoluteString], error);
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
    return [[CK2FileManager URLWithPath:@"/" isDirectory:YES hostURL:self] absoluteURL];
}

- (NSURL *)ck2_parentURL
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLParentDirectoryURLKey error:&error])
    {
        if ((value == nil) || [value isKindOfClass:[NSURL class]])
        {
            return value;
        }
        else
        {
            NSLog(@"Parent of URL %@ is not an URL type: %@", self, [value class]);
        }
    }
    else
    {
        NSLog(@"Error getting parent URL for URL %@: %@", self, error);
    }
    return nil;
}


- (BOOL)ck2_isAncestorOfURL:(NSURL *)url
{
    NSURL   *tempURL;
    
    tempURL = url;
    
    while (![tempURL isEqual:self])
    {
        if (tempURL == nil)
        {
            return NO;
        }
        tempURL = [tempURL ck2_parentURL];
    }
    return YES;
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



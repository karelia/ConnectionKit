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
#import <Connection/CK2FileManager.h>
#import <dispatch/dispatch.h>

@interface CK2PlaceholderURL : NSURL
@end


@implementation NSURL (CK2OpenPanel)

+ (NSURL *)loadingURL
{
    return [[[CK2PlaceholderURL alloc] initWithString:@"Loading…"] autorelease];
}

+ (NSURL *)errorURL
{
    return [[[CK2PlaceholderURL alloc] initWithString:@"Error"] autorelease];
}


- (BOOL)isPlaceholder
{
    return NO;
}

- (NSString *)displayName
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

- (NSImage *)icon
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
        NSString        *type;
        
        if ([self canHazChildren])
        {
            return [NSImage imageNamed:NSImageNameFolder];
        }
        type = [self pathExtension];
        
        if ([type isEqual:@"app"])
        {
            return [NSImage imageNamed:NSImageNameApplicationIcon];
        }
        return [[NSWorkspace sharedWorkspace] iconForFileType:type];
    }
    return nil;
}

- (NSDate *)dateModified
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

- (NSString *)kind
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

        if ([self canHazChildren])
        {
            return @"Folder";
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

- (NSNumber *)size
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

- (BOOL)isDirectory
{
    id          value;
    NSError     *error;
    
    if ([self getResourceValue:&value forKey:NSURLIsDirectoryKey error:&error])
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

- (BOOL)isPackage
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

- (BOOL)canHazChildren
{
    return [self isDirectory] && ![self isPackage];
}

- (NSURL *)root
{
    if ([self isFileURL])
    {
        id          value;
        NSError     *error;
        
        if ([self getResourceValue:&value forKey:NSURLVolumeURLKey error:&error])
        {
            return value;
        }
        else
        {
            NSLog(@"Error getting root for URL %@: %@", [self absoluteString], error);
        }
        return nil;
    }
    else
    {
        return [CK2FileManager URLWithPath:@"/" relativeToURL:self];
    }
}

- (void)enumerateFromRoot:(void (^)(NSURL *url, BOOL *stop))block
{
    NSURL               *tempURL;
    NSArray             *targetComponents;
    NSUInteger          i, count;
    
    if (block != NULL)
    {
        BOOL    stop;
        
        targetComponents = [self pathComponents];
        count = [targetComponents count];
        
        tempURL = [self root];
        
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

- (NSURL *)URLByDeletingTrailingSlash
{
    NSString    *path;
    
    path = [self path];
    if ([path hasSuffix:@"/"])
    {
        path = [path substringToIndex:[path length] - 1];
    }
    // Quite the rigamarole just to get an URL without the trailing slash
    return [[NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] relativeToURL:[self root]] absoluteURL];
}

@end


@implementation CK2PlaceholderURL

- (BOOL)isPlaceholder
{
    return YES;
}

- (NSString *)displayName
{
    return [[self absoluteString] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

- (NSImage *)icon
{
    return nil;
}

- (NSDate *)dateModified
{
    return nil;
}

- (NSString *)kind
{
    return @"";
}

- (NSString *)sizeString
{
    return @"";
}

- (BOOL)isDirectory
{
    return NO;
}

- (BOOL)canHazChildren
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



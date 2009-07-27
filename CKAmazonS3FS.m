//
//  S3MacFUSE_Filesystem.m
//  ConnectionKit
//
//  Created by Mike on 22/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//
#import <sys/xattr.h>
#import <sys/stat.h>
#import "CKAmazonS3FS.h"
#import <MacFUSE/MacFUSE.h>

#import "CKFSItemInfo.h"
#import "CK_AmazonS3ServiceInfoParser.h"
#import "CK_AmazonS3BucketInfoParser.h"
#import "CKAmazonS3Handle.h"


// Category on NSError to  simplify creating an NSError based on posix errno.
@interface NSError (POSIX)
+ (NSError *)errorWithPOSIXCode:(int)code;
@end
@implementation NSError (POSIX)
+ (NSError *)errorWithPOSIXCode:(int) code {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}
@end


#pragma mark -


@interface CKAmazonS3FS (Private)
- (NSData *)dataWithRequest:(NSURLRequest *)request
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error;
@end


#pragma mark -


// NOTE: It is fine to remove the below sections that are marked as 'Optional'.
// To create a working write-able file system, you must implement all non-optional
// methods fully and have them return errors correctly.

// The core set of file system operations. This class will serve as the delegate
// for GMUserFileSystemFilesystem. For more details, see the section on 
// GMUserFileSystemOperations found in the documentation at:
// http://macfuse.googlecode.com/svn/trunk/core/sdk-objc/Documentation/index.html
@implementation CKAmazonS3FS

#pragma mark Init

- (id)initWithCredential:(NSURLCredential *)credential;
{
    [self init];
    _credential = [credential retain];
    return self;
}

#pragma mark Directory Contents

- (CKFSItemInfo *)loadContentsOfDirectoryAtPath:(NSString *)path error:(NSError **)outError;
{
    CKFSItemInfo *result;
    
    if ([path isEqualToString:@"/"])
    {
        result = [self serviceInfo:outError];
    }
    else
    {
        // Need to convert the path into bucket & prefix. e.g.
        //  /foo/bar  >>  foo, bar/
        //  /foo/bar/baz  >>  foo, bar/baz/
        NSString *prefix = nil;
        
        NSArray *pathComponents = [path pathComponents];
        if ([pathComponents count] >= 3)
        {
            NSArray *prefixComponents = [pathComponents subarrayWithRange:
                                         NSMakeRange(2,[pathComponents count] - 2)];
            prefix = [[NSString pathWithComponents:prefixComponents]
                      stringByAppendingString:@"/"];
        }
        
        result = [self infoForBucket:[[path pathComponents] objectAtIndex:1]
                              prefix:prefix 
                           delimiter:@"/"
                               error:outError];
    }
    
    return result;
}

#pragma mark Getting and Setting Attributes

- (CKFSItemInfo *)loadAttributesOfItemAtPath:(NSString *)path
                                    userData:(id)userData
                                       error:(NSError **)outError;
{
    CKFSItemInfo *result = nil;
    
    // No need to fetch service or bucket attributes, we know them all already
    if ([path isEqualToString:@"/"])
    {
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:NSFileTypeDirectory
                                                               forKey:NSFileType];
        result = [CKFSItemInfo infoWithFileAttributes:attributes];
    }
    else if ([[path pathComponents] count] == 2)
    {
        NSString *bucket = [[path pathComponents] objectAtIndex:1];
        CKFSItemInfo *serviceInfo = [self loadContentsOfDirectoryAtPath:@"/" error:outError];
        for (CKFSItemInfo *aBucket in [serviceInfo directoryContents])
        {
            if ([[aBucket filename] isEqualToString:bucket])
            {
                result = aBucket;
                break;
            }
        }
    }
    else
    {
        // Got no good way to know if this is a directory or file. Try directory first then fall back to file
        
        // Need to convert the path into bucket & prefix. e.g.
        //  /foo/bar  >>  foo, bar/
        //  /foo/bar/baz  >>  foo, bar/baz/
        NSArray *pathComponents = [path pathComponents];
        NSString *bucket = [pathComponents objectAtIndex:1];
        NSArray *keyComponents = [pathComponents subarrayWithRange:
                                  NSMakeRange(2, [pathComponents count] - 2)];
        
        NSString *key = [NSString pathWithComponents:keyComponents];
        NSString *dirKey = [key stringByAppendingString:@"/"];
        
        result = [self infoForObjectForKey:dirKey
                                  inBucket:bucket
                                     error:outError];
        
        if (!result)
        {
            result = [self infoForObjectForKey:key
                                      inBucket:bucket
                                         error:outError];
        }
    }
    
    
    return result;
}

#pragma mark File Contents

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error
{
    if (mode == O_RDONLY)
    {
        // Create a read stream for the URL but don't open it until reading takes place
        NSURL *URL = [[NSURL alloc] initWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                                     relativeToURL:[NSURL URLWithString:@"http://s3.amazonaws.com/"]];
        
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
        [URL release];
        
        CKAmazonS3Handle *handle = [[CKAmazonS3Handle alloc] initWithRequest:request credential:_credential];
        [request release];
        
        *userData = [handle autorelease];
        return YES;
    }
    else
    {
        *error = [NSError errorWithPOSIXCode:ENOENT];
        return NO;
    }
}

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData
{
    CKAmazonS3Handle *handle = userData;
    [handle close];
}

- (int)readFileAtPath:(NSString *)path 
             userData:(id)userData
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error
{
    CKAmazonS3Handle *handle = userData;
    int result = [handle read:(uint8_t *)buffer size:size offset:offset error:error];
    return result;
}

- (int)XwriteFileAtPath:(NSString *)path 
              userData:(id)userData
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error
{
    return size;
}

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error
{
    if ([[path pathComponents] count] == 2)
    {
        return [self createBucket:[path lastPathComponent] error:error];
    }
    else
    {
        return [self createDirectoryObjectAtPath:path error:error];
    }
}

- (BOOL)XcreateFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
                userData:(id *)userData
                   error:(NSError **)error
{
    return YES;
}

#pragma mark Removing an Item

- (BOOL)removeDirectoryAtPath:(NSString *)path error:(NSError **)error; 
{
    // Because S3 fakes directories with objects, must doctor the deletion path to handle them
    if ([[path pathComponents] count] > 2) path = [path stringByAppendingString:@"/"];
    return [self deleteItemAtPath:path error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error
{
    return [self deleteItemAtPath:path error:error];
}

@end


#pragma mark -


@implementation CKAmazonS3FS (UnderlyingOperations)

#pragma mark Service

- (CKFSItemInfo *)serviceInfo:(NSError **)outError;
{
    NSURL *URL = [[NSURL alloc] initWithString:@"http://s3.amazonaws.com/"];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    NSData *data = [self dataWithRequest:request response:NULL error:outError];
    [request release];
    [URL release];
    
    
    if (data)
    {
        CK_AmazonS3ServiceInfoParser *parser = [[CK_AmazonS3ServiceInfoParser alloc] init];
        CKFSItemInfo *fileInfo = [parser parseData:data];
        [parser release];
        
        return fileInfo;
    }
    
    return nil;
}

#pragma mark Buckets

- (BOOL)createBucket:(NSString *)bucket error:(NSError **)outError;
{
    NSString *URLString = [[NSString alloc] initWithFormat:
                           @"http://%@.s3.amazonaws.com/",
                           [bucket stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    NSURL *URL = [[NSURL alloc] initWithString:URLString];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    NSData *data = [self dataWithRequest:request response:NULL error:outError];
    [request release];
    [URL release];
    [URLString release];
    
    return (data != nil);
}

- (CKFSItemInfo *)infoForBucket:(NSString *)bucket
                         prefix:(NSString *)prefix
                      delimiter:(NSString *)delimiter
                          error:(NSError **)outError;
{
    NSMutableString *URLString = [NSMutableString stringWithFormat:
                                  @"http://%@.s3.amazonaws.com/",
                                  bucket];
    if (prefix)
    {
        [URLString appendFormat:
         @"?prefix=%@",
         [prefix stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        if (delimiter) [URLString appendFormat:@"&delimiter=%@", delimiter];
    }
    else if (delimiter)
    {
        [URLString appendFormat:@"?delimiter=%@", delimiter];
    }
    
    NSURL *URL = [[NSURL alloc] initWithString:URLString];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    NSData *data = [self dataWithRequest:request response:NULL error:outError];
    [request release];
    [URL release];
    
    
    if (data)
    {
        CK_AmazonS3BucketInfoParser *parser = [[CK_AmazonS3BucketInfoParser alloc] init];
        CKFSItemInfo *fileInfo = [parser parseData:data];
        [parser release];
        return fileInfo;
    }
    
    return nil;
}

#pragma mark Objects

- (BOOL)createDirectoryObjectAtPath:(NSString *)path error:(NSError **)outError;
{
    NSString *escapedPath = [[path stringByAppendingString:@"/"]
                             stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *URL = [[NSURL alloc] initWithString:escapedPath
                                 relativeToURL:[NSURL URLWithString:@"http://s3.amazonaws.com/"]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"PUT"];
    
    NSData *data = [self dataWithRequest:request response:NULL error:outError];
    
    
    // Tidy up
    [request release];
    [URL release];
    
    return (data != nil);
}

- (CKFSItemInfo *)infoForObjectForKey:(NSString *)key
                             inBucket:(NSString *)bucket
                                error:(NSError **)outError;
{
    CKMutableFSItemInfo *result = nil;
    
    
    NSString *URLString = [NSString stringWithFormat:
                           @"http://%@.s3.amazonaws.com/%@",
                           bucket,
                           [key stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSURL *URL = [[NSURL alloc] initWithString:URLString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"HEAD"];
    [URL release];
    
    
    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self dataWithRequest:request response:&response error:&error];
    [request release];
    
    if (data)
    {
        NSString *fileType = ([key hasSuffix:@"/"] ? NSFileTypeDirectory : NSFileTypeRegular);
        result = [[CKMutableFSItemInfo alloc] initWithFilename:nil
                                                    attributes:[NSDictionary dictionaryWithObject:fileType
                                                                                           forKey:NSFileType]];
        
        if (response)
        {
            [result setValue:[NSNumber numberWithLongLong:[response expectedContentLength]]
            forFileAttribute:NSFileSize];
        }
    }
    else
    {
        *outError = [NSError errorWithPOSIXCode:ENOENT];
    }
    
    
    
    return result;
}

#pragma mark General

- (BOOL)deleteItemAtPath:(NSString *)path error:(NSError **)outError;
{
    NSString *escapedPath = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *URL = [[NSURL alloc] initWithString:escapedPath
                                 relativeToURL:[NSURL URLWithString:@"http://s3.amazonaws.com/"]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"DELETE"];
    
    NSData *data = [self dataWithRequest:request response:NULL error:outError];
    
    
    // Tidy up
    [request release];
    [URL release];
    
    return (data != nil);
}

#pragma mark Connection

// Convenience to load all the data for a request at once
- (NSData *)dataWithRequest:(NSURLRequest *)request
                   response:(NSHTTPURLResponse **)response
                      error:(NSError **)outError
{
    CKAmazonS3Handle *handle = [[CKAmazonS3Handle alloc] initWithRequest:request credential:_credential];
    
    NSData *result = [handle readDataToEndOfFile:outError];
    if (response) *response = [handle response];
    
    [handle release];
    return result;
}

@end


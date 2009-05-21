//
//  CKFileConnectionProtocol.m
//  Connection
//
//  Created by Mike on 23/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileConnectionProtocol.h"

#import "CKConnectionError.h"
#import "CKConnectionProtocol1.h"


@implementation CKFileConnectionProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request;
{
    NSURL *URL = [request URL];
    
    NSString *scheme = [URL scheme];
    if (scheme && [scheme isEqualToString:@"file"])
    {
        NSString *host = [URL host];
        if (!host || [host isEqualToString:@""] || [host isEqualToString:@"localhost"])
        {
            return YES;
        }
    }
    
    return NO;
}

- (id)initWithRequest:(NSURLRequest *)request client:(id <CKConnectionProtocolClient>)client
{
    self = [super initWithRequest:request client:client];
    if (self)
    {
        _fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_fileManager release];
    [super dealloc];
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    [[self client] connectionProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Writing data to %@", @"file transcript")
                         toTranscript:CKTranscriptSent, path];
	
	BOOL result = [_fileManager createFileAtPath:path
                                         contents:data
                                       attributes:nil];
    
    if (result)
    {
        //need to send the amount of bytes transferred.
        [[self client] connectionProtocol:self didUploadDataOfLength:[data length]];
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  LocalizedStringInConnectionKitBundle(@"Failed to upload data", @"FileConnection copy data error"), NSLocalizedDescriptionKey,
                                  path, NSFilePathErrorKey,nil];
        NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:userInfo];
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)downloadContentsOfFileAtPath:(NSString *)path
{
    NSData *data = [_fileManager contentsAtPath:path];
    if (data)
    {
        [[self client] connectionProtocol:self didDownloadData:data];
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Unable to download data", @"File connection download failure"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:userInfo];
		[[self client] connectionProtocol:self currentOperationDidFailWithError:error];
    }
}

- (void)fetchContentsOfDirectoryAtPath:(NSString *)path
{
    NSArray *array = [_fileManager directoryContentsAtPath:path];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSString *file = [NSString stringWithFormat:@"%@/%@", path, cur];
		NSMutableDictionary *attribs = [NSMutableDictionary dictionaryWithDictionary:[_fileManager fileAttributesAtPath:file
                                                                                                            traverseLink:NO]];
		[attribs setObject:cur forKey:cxFilenameKey];
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			NSString *target = [file stringByResolvingSymlinksInPath];
			BOOL isDir;
			[_fileManager fileExistsAtPath:target isDirectory:&isDir];
			if (isDir && ![target hasSuffix:@"/"])
			{
				target = [target stringByAppendingString:@"/"];
			}
			[attribs setObject:target forKey:cxSymbolicLinkTargetKey];
		}
		
		[packaged addObject:attribs];
	}
	
	[[self client] connectionProtocol:self didLoadContentsOfDirectory:packaged];
    [[self client] connectionProtocolDidFinishCurrentOperation:self];
}

- (void)createDirectoryAtPath:(NSString *)path
{
	BOOL result = [_fileManager createDirectoryAtPath:path attributes:nil];
    
    // Signal that the directory was created if one already exists
    if (!result)
    {
        result = ([_fileManager fileExistsAtPath:path isDirectory:&result] && !result);
    }
    
    if (result)
    {
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
							LocalizedStringInConnectionKitBundle(@"Could not create directory", @"FileConnection create directory error"), NSLocalizedDescriptionKey,
							path, NSFilePathErrorKey,
                            nil];		
		
        NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:ui];
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    [[self client] connectionProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Renaming %@ to %@", @"file transcript")
                         toTranscript:CKTranscriptSent, fromPath, toPath];
	
	if ([_fileManager movePath:fromPath toPath:toPath handler:self])
    {
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObject:localizedDescription forKey:NSLocalizedDescriptionKey];
		NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:userInfo];
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path
{	
	NSDictionary *attribs = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:posixPermissions]
                                                        forKey:NSFilePosixPermissions];
	
	if ([_fileManager changeFileAttributes:attribs atPath:path])
    {
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Could not change file permissions", @"FileConnection set permissions error"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:userInfo];
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)deleteItemAtPath:(NSString *)path
{
    [[self client] connectionProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Deleting File %@", @"file transcript")
                         toTranscript:CKTranscriptSent, path];
	
	if ([_fileManager removeFileAtPath:path handler:self])
    {
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete file: %@", @"error for deleting a file"), path];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:CKConnectionErrorUnknown userInfo:userInfo];		
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
	}
}

@end

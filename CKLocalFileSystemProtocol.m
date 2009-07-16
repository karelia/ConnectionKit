//
//  CKFileConnectionProtocol.m
//  Connection
//
//  Created by Mike on 23/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKLocalFileSystemProtocol.h"

#import "CKError.h"
#import "CKConnectionProtocol1.h"


@implementation CKLocalFileSystemProtocol

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

- (id)initWithRequest:(NSURLRequest *)request client:(id <CKFileTransferProtocolClient>)client
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
    [[self client] FSProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Writing data to %@", @"file transcript")
                         toTranscript:CKTranscriptSent, path];
	
	BOOL result = [_fileManager createFileAtPath:path
                                         contents:data
                                       attributes:nil];
    
    if (result)
    {
        //need to send the amount of bytes transferred.
        [[self client] FSProtocol:self didUploadDataOfLength:[data length]];
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  LocalizedStringInConnectionKitBundle(@"Failed to upload data", @"FileConnection copy data error"), NSLocalizedDescriptionKey,
                                  path, NSFilePathErrorKey,nil];
        NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:userInfo];
        [[self client] FSProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)downloadContentsOfFileAtPath:(NSString *)path
{
    NSData *data = [_fileManager contentsAtPath:path];
    if (data)
    {
        [[self client] FSProtocol:self didDownloadData:data];
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Unable to download data", @"File connection download failure"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:userInfo];
		[[self client] FSProtocol:self currentOperationDidFailWithError:error];
    }
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
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
							LocalizedStringInConnectionKitBundle(@"Could not create directory", @"FileConnection create directory error"), NSLocalizedDescriptionKey,
							path, NSFilePathErrorKey,
                            nil];		
		
        NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:ui];
        [[self client] FSProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    [[self client] FSProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Renaming %@ to %@", @"file transcript")
                         toTranscript:CKTranscriptSent, fromPath, toPath];
	
	if ([_fileManager movePath:fromPath toPath:toPath handler:self])
    {
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObject:localizedDescription forKey:NSLocalizedDescriptionKey];
		NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:userInfo];
        [[self client] FSProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path
{	
	NSDictionary *attribs = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:posixPermissions]
                                                        forKey:NSFilePosixPermissions];
	
	if ([_fileManager changeFileAttributes:attribs atPath:path])
    {
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Could not change file permissions", @"FileConnection set permissions error"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:userInfo];
        [[self client] FSProtocol:self currentOperationDidFailWithError:error];
	}
}

- (void)deleteItemAtPath:(NSString *)path
{
    [[self client] FSProtocol:self
                         appendFormat:LocalizedStringInConnectionKitBundle(@"Deleting File %@", @"file transcript")
                         toTranscript:CKTranscriptSent, path];
	
	if ([_fileManager removeFileAtPath:path handler:self])
    {
        [[self client] FSProtocolDidFinishCurrentOperation:self];
    }
    else
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete file: %@", @"error for deleting a file"), path];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknown userInfo:userInfo];		
        [[self client] FSProtocol:self currentOperationDidFailWithError:error];
	}
}

@end

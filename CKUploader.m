//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"

#import "CKConnectionRegistry.h"
#import "CKFileConnection.h"


@implementation CKUploader

#pragma mark Lifecycle

- (id)initWithRequest:(CKConnectionRequest *)request
 filePosixPermissions:(unsigned long)customPermissions
              options:(CKUploadingOptions)options;
{
    if (self = [self init])
    {
        _request = [request copy];
        _permissions = customPermissions;
        _options = options;
        
        _connection = [[[CKConnectionRegistry sharedConnectionRegistry] connectionWithRequest:request] retain];
        _rootRecord = [[CKTransferRecord rootRecordWithPath:[[request URL] path]] retain];
        _baseRecord = [_rootRecord retain];
    }
    return self;
}

+ (CKUploader *)uploaderWithRequest:(CKConnectionRequest *)request
               filePosixPermissions:(NSNumber *)customPermissions
                            options:(CKUploadingOptions)options;
{
    NSParameterAssert(request);
    return [[[self alloc] initWithRequest:request
                     filePosixPermissions:(customPermissions ? [customPermissions unsignedLongValue] : 0644)
                                  options:options] autorelease];
}

- (void)dealloc
{
    [_connection setDelegate:nil];
    
    [_request release];
    [_connection release];
    [_rootRecord release];
    [_baseRecord release];
    
    [super dealloc];
}

#pragma mark Properties

@synthesize delegate = _delegate;

@synthesize rootTransferRecord = _rootRecord;
@synthesize baseTransferRecord = _baseRecord;

- (unsigned long)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
{
    unsigned long result = _permissions;
    if (directory) result = (result | 0111);
    return result;
}

#pragma mark Publishing

/*  Creates the specified directory including any parent directories that haven't already been queued for creation.
 *  Returns a CKTransferRecord used to represent the directory during publishing.
 */
- (CKTransferRecord *)createDirectoryAtPath:(NSString *)path
{
    NSParameterAssert(path);
    
    
    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    [_connection connect];	// ensure we're connected
    
    
    // Ensure the parent directory is created first
    NSString *parentDirectoryPath = [path stringByDeletingLastPathComponent];
    CKTransferRecord *parent = [self createDirectoryAtPath:parentDirectoryPath];
    
    
    // Create the directory if it hasn't been already
    CKTransferRecord *result = nil;
    int i;
    for (i = 0; i < [[parent contents] count]; i++)
    {
        CKTransferRecord *aRecord = [[parent contents] objectAtIndex:i];
        if ([[aRecord name] isEqualToString:[path lastPathComponent]])
        {
            result = aRecord;
            break;
        }
    }
    
    if (!result)
    {
        // This code will not set permissions for the document root or its parent directories as the
        // document root is created before this code gets called
        [_connection createDirectoryAtPath:path
                          posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:YES]]];
        
        result = [CKTransferRecord recordWithName:[path lastPathComponent] size:0];
        [parent addContent:result];
    }
    
    return result;
}

- (void)willUploadToPath:(NSString *)path;
{
    [self createDirectoryAtPath:[path stringByDeletingLastPathComponent]];
}

- (void)didEnqueueUpload:(CKTransferRecord *)record toPath:(NSString *)path
{
    // Need to use -setName: otherwise the record will have the full path as its name
    [record setName:[path lastPathComponent]];
    
    CKTransferRecord *parent = [self createDirectoryAtPath:[path stringByDeletingLastPathComponent]];
    [parent addContent:record];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    [self willUploadToPath:path];
    
    CKTransferRecord *result = [_connection uploadData:data
                                                toPath:path
                                      posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:NO]]];
    
    [self didEnqueueUpload:result toPath:path];
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path;
{
    [self willUploadToPath:path];
    
    CKTransferRecord *result = [_connection uploadFileAtURL:url
                                                toPath:path
                                           posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:NO]]];
    
    [self didEnqueueUpload:result toPath:path];
    return result;
}

- (void)finishUploading;
{
    [_connection disconnect];
}

- (void)cancel;
{
    [_connection forceDisconnect];
    [_connection setDelegate:nil];
}

#pragma mark Connection Delegate

- (void)connection:(id <CKPublishingConnection>)con didDisconnectFromHost:(NSString *)host;
{
    if (!_connection) return; // we've already finished in which case
    
    [[self delegate] uploaderDidFinishUploading:self];
}

- (void)connection:(id<CKPublishingConnection>)con didReceiveError:(NSError *)error;
{
    if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return; //don't alert users to the fact it already exists, silently fail
	}
	else if ([error code] == 550 || [[[error userInfo] objectForKey:@"protocol"] isEqualToString:@"createDirectory:"] )
	{
		return;
	}
	else if ([con isKindOfClass:NSClassFromString(@"WebDAVConnection")] && 
			 ([[[error userInfo] objectForKey:@"directory"] isEqualToString:@"/"] || [error code] == 409 || [error code] == 204 || [error code] == 404))
	{
		// web dav returns a 409 if we try to create / .... which is fair enough!
		// web dav returns a 204 if a file to delete is missing.
		// 404 if the file to delete doesn't exist
		
		return;
	}
	else if ([error code] == kSetPermissions) // File connection set permissions failed ... ignore this (why?)
	{
		return;
	}
	else
	{
		[[self delegate] uploader:self didFailWithError:error];
	}
}

- (void)connection:(id <CKPublishingConnection>)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Hand off to the delegate for auth
    id <CKUploaderDelegate> delegate = [self delegate];
    if (delegate)
    {
        [[self delegate] uploader:self didReceiveAuthenticationChallenge:challenge];
    }
    else
    {
        if ([challenge previousFailureCount] == 0)
        {
            NSURLCredential *credential = [challenge proposedCredential];
            if (!credential)
            {
                credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:[challenge protectionSpace]];
            }
            
            if (credential)
            {
                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                return;
            }
        }
        
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

@end

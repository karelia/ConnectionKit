/*
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#import "CKDotMacConnection.h"
#import "CKAbstractConnection.h"
#import "CKDAVDirectoryContentsRequest.h"
#import "CKDAVCreateDirectoryRequest.h"
#import "CKDAVUploadFileRequest.h"
#import "CKDAVDeleteRequest.h"
#import "CKDAVResponse.h"
#import "CKDAVDirectoryContentsResponse.h"
#import "CKDAVCreateDirectoryResponse.h"
#import "CKDAVUploadFileResponse.h"
#import "CKDAVDeleteResponse.h"
#import "NSData+Connection.h"
#import <Security/Security.h>
#import "CKConnectionThreadManager.h"
#import "NSString+Connection.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"

@interface CKWebDAVConnection (DotMac)
- (void)processResponse:(CKDAVResponse *)response;
- (void)processFileCheckingQueue;
@end

@implementation CKDotMacConnection

#pragma mark class methods

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forURLScheme:@"dotmac"];
	[pool release];
}

+ (NSString *)name
{
	return @"MobileMe";
}

+ (NSArray *)URLSchemes
{
	return [NSArray arrayWithObjects:@"http", @"dotmac", nil];
}

#pragma mark init methods

- (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password
{
	BOOL result = NO;
	
	NSString *accountName = [[NSUserDefaults standardUserDefaults] objectForKey:@"iToolsMember"];
	if (accountName)
	{
		SecKeychainItemRef item = nil;
		OSStatus theStatus = noErr;
		char *buffer;
		UInt32 passwordLen;
		
		char *utf8 = (char *)[accountName UTF8String];
		theStatus = SecKeychainFindGenericPassword(NULL,
												   6,
												   "iTools",
												   strlen(utf8),
												   utf8,
												   &passwordLen,
												   (void *)&buffer,
												   &item);
		
		if (noErr == theStatus)
		{
			if (passwordLen > 0)
			{
				*password = [[[NSString alloc] initWithBytes:buffer length:passwordLen encoding:[NSString defaultCStringEncoding]] autorelease];
			}
			else
			{
				*password = @""; // if we have noErr but also no length, password is empty
			}

			// release buffer allocated by SecKeychainFindGenericPassword
			theStatus = SecKeychainItemFreeContent(NULL, buffer);
			
			*account = accountName;
			result = YES;
		}
	}
	
	return result;
}

// TODO: Move to the new authentication model
- (id)initWithURL:(NSURL *)URL
{
	if (URL)
    {
        NSParameterAssert([[URL host] isEqualToString:@"idisk.mac.com"]);
    }
    
    NSString *user = [URL user];
	NSString *password = [URL password];
	
	if (user && password)
	{
		
        if (self = [super initWithURL:URL])
		{
			myCurrentDirectory = [[NSString alloc] initWithFormat:@"/%@/", [URL user]];
		}
	}
	else
	{
		if (![self getDotMacAccountName:&user password:&password])
		{
			[self release];
			return nil;
		}
		
		if (self = [super initWithURL:[NSURL URLWithString:@"http://idisk.mac.com"]])
		{
			myCurrentDirectory = [[NSString stringWithFormat:@"/%@/", user] retain];
		}
	}

	return self;
}

#pragma mark -
#pragma mark WebDAV Overrides

- (void)processResponse:(CKDAVResponse *)response
{
	KTLog(CKProtocolDomain, KTLogDebug, @"%@", response);
	switch (GET_STATE)
	{
		case CKConnectionAwaitingDirectoryContentsState:
		{
			CKDAVDirectoryContentsResponse *dav = (CKDAVDirectoryContentsResponse *)response;
			NSError *error = nil;
			NSString *localizedDescription = nil;
			NSArray *contents = [NSArray array];
			
			switch ([dav code])
			{
				case 200:
				case 207: //multi-status
				{
					if (_flags.directoryContents)
					{
						contents = [dav directoryContents];
						[self cacheDirectory:[dav path] withContents:contents];
					}
					break;
				}
				case 404:
				{		
					localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"There is no MobileMe access to the directory", @"MobileMe Directory Contents Error"), [dav path]];
					break;
				}
				default: 
				{
					localizedDescription = @"Unknown Error Occurred";
					break;
				}
			}
			
			if (localizedDescription)
			{
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  localizedDescription, NSLocalizedDescriptionKey,
										  [dav className], @"DAVResponseClass",
										  [dav path], NSFilePathErrorKey, nil];
				error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];				
			}
			
			if (_flags.directoryContents)
				[_forwarder connection:self didReceiveContents:contents ofDirectory:[[dav path] stringByDeletingFirstPathComponent] error:error];
			
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionCreateDirectoryState:
		{
			CKDAVCreateDirectoryResponse *dav = (CKDAVCreateDirectoryResponse *)response;
			NSString *localizedDescription = nil;
			NSError *error = nil;
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			
			switch ([dav code])
			{
				case 201: 
				{
					break; //Do Nothing
				}
				case 403:
				{		
					localizedDescription = LocalizedStringInConnectionKitBundle(@"The server does not allow the creation of directories at the current location", @"MobileMe Create Directory Error");
						//we fake the directory exists as this is usually the case if it is the root directory
					[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 405:
				{		
					if (_flags.isRecursiveUploading)
					{
						localizedDescription = LocalizedStringInConnectionKitBundle(@"The directory already exists", @"MobileMe Create Directory Error");
						[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					}
					break;
				}
				case 409:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @"MobileMe Create Directory Error");
					break;
				}
				case 415:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"The body of the request is not supported", @"MobileMe Create Directory Error");
					break;
				}
				case 507:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"Insufficient storage space available", @"MobileMe Create Directory Error");
					break;
				}
				default: 
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"An unknown error occured", @"MobileMe Create Directory Error");
					break;
				}
			}
			if (localizedDescription)
			{
				[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
				[userInfo setObject:[dav className] forKey:@"DAVResponseClass"];
				[userInfo setObject:[[dav request] description] forKey:@"DAVRequest"];
				[userInfo setObject:[(CKDAVCreateDirectoryRequest *)[dav request] path] forKey:NSFilePathErrorKey];
				error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
			}
			
			if (_flags.createDirectory)
				[_forwarder connection:self didCreateDirectory:[[dav directory] stringByDeletingFirstPathComponent] error:error];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionUploadingFileState:
		{
			CKDAVUploadFileResponse *dav = (CKDAVUploadFileResponse *)response;
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					break; //Do Nothing
				}
				case 409:
				{		
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  LocalizedStringInConnectionKitBundle(@"Parent Folder does not exist", @"MobileMe File Uploading Error"), NSLocalizedDescriptionKey,
											  [[self currentUpload] remotePath], NSFilePathErrorKey, 
											  [dav className], @"DAVResponseClass", nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
				break;
			}
			
			CKInternalTransferRecord *upload = [[self currentUpload] retain];			
			[self dequeueUpload];
			
			if (_flags.uploadFinished)
				[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
			
			[upload release];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionDeleteFileState:
		{
			CKDAVDeleteResponse *dav = (CKDAVDeleteResponse *)response;
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					break; //Do Nothing
				}
				default:
				{
					NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"MobileMe file deletion error"), [[self currentDeletion] stringByDeletingFirstPathComponent]];
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  [[dav request] description], @"DAVRequest",
											  [dav className], @"DAVResponseClass",
											  [[self currentDeletion] stringByDeletingFirstPathComponent], NSFilePathErrorKey, nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
			}
			NSString *deletionPath = [[self currentDeletion] retain];
			[self dequeueDeletion];
			
			if (_flags.deleteFile)
				[_forwarder connection:self didDeleteFile:[deletionPath stringByDeletingFirstPathComponent] error:error];
			
			[deletionPath release];
		
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionDeleteDirectoryState:
		{
			CKDAVDeleteResponse *dav = (CKDAVDeleteResponse *)response;
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					break; //Do Nothing
				}
				default:
				{
					NSString *path = [[self currentDeletion] stringByDeletingFirstPathComponent];
					NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete directory", @"MobileMe Directory Deletion Error"), path];
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  [[dav request] description], @"DAVRequest",
											  [dav className], @"DAVResponseClass",
											  path, NSFilePathErrorKey, nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code]  userInfo:userInfo];
				}
			}
			NSString *deletionPath = [[self currentDeletion] retain];
			[self dequeueDeletion];
			
			if (_flags.deleteDirectory)
				[_forwarder connection:self didDeleteDirectory:[deletionPath stringByDeletingFirstPathComponent] error:error];
			
			[deletionPath release];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		default: [super processResponse:response];
	}
}

- (void)stream:(id<OutputStream>)stream readBytesOfLength:(unsigned)length
{
	if (length == 0) return;
	if (GET_STATE == CKConnectionDownloadingFileState)
	{
		CKInternalTransferRecord *download = [self currentDownload];
		bytesTransferred += length;
		if (bytesToTransfer > 0) // intel gives a crash for div by 0
		{
			int percent = (bytesTransferred * 100) / bytesToTransfer;
			
			if (_flags.downloadPercent)
			{
				[_forwarder connection:self 
							  download:[[download remotePath] stringByDeletingFirstPathComponent]
						  progressedTo:[NSNumber numberWithInt:percent]];
			}
			
			if ([download delegateRespondsToTransferProgressedTo])
			{
				[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		
		
		if (_flags.downloadProgressed)
		{
			[_forwarder connection:self
						  download:[[download remotePath] stringByDeletingFirstPathComponent]
			  receivedDataOfLength:length];
		}
		if ([download delegateRespondsToTransferTransferredData])
		{
			[[download delegate] transfer:[download userInfo] transferredDataOfLength:length];
		}
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	if (length == 0) return;
	if (GET_STATE == CKConnectionUploadingFileState)
	{
		if (transferHeaderLength > 0)
		{
			if (length <= transferHeaderLength)
			{
				transferHeaderLength -= length;
			}
			else
			{
				length -= transferHeaderLength;
				transferHeaderLength = 0;
				bytesTransferred += length;
			}
		}
		else
		{
			bytesTransferred += length;
		}
		
		CKInternalTransferRecord *upload = [self currentUpload];
		
		if (bytesToTransfer > 0) // intel gives a crash for div by 0
		{
			int percent = (bytesTransferred * 100) / bytesToTransfer;
			if (_flags.uploadPercent)
			{
				[_forwarder connection:self 
								upload:[upload remotePath]
						  progressedTo:[NSNumber numberWithInt:percent]];
			}
			if ([upload delegateRespondsToTransferProgressedTo])
			{
				[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		if (_flags.uploadProgressed)
		{
			[_forwarder connection:self 
							upload:[upload remotePath]
				  sentDataOfLength:length];
		}
		if ([upload delegateRespondsToTransferTransferredData])
		{
			[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:length];
		}
	}
}

#pragma mark -
#pragma mark Protocol Overrides

- (void)changeToDirectory:(NSString *)dirPath
{
	[super changeToDirectory:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:dirPath]];
}

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:[dirPath stringByDeletingFirstPathComponent] error:nil];
	}
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:CKConnectionIdleState];
}

- (NSString *)currentDirectory
{
	return [[super currentDirectory] stringByDeletingFirstPathComponent];
}

- (NSDictionary *)currentDownload
{
	CKInternalTransferRecord *returnValue = [[super currentDownload] copy];
	
	[returnValue setRemotePath:[[returnValue remotePath] stringByDeletingFirstPathComponent]];
	
	return [returnValue autorelease];
}

- (CKInternalTransferRecord *)currentUpload
{
	CKInternalTransferRecord *returnValue = [[super currentUpload] copy];
  
	[returnValue setRemotePath:[[returnValue remotePath] stringByDeletingFirstPathComponent]];
  
	return [returnValue autorelease];
}

- (NSString *)rootDirectory
{
	return [[super rootDirectory] stringByDeletingFirstPathComponent];
}

- (void)createDirectory:(NSString *)dirPath
{
	[super createDirectory:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:dirPath]];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	[self createDirectory:dirPath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	[super setPermissions:permissions
				  forFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:path]];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSString *from = [[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:fromPath];
	NSString *to = [[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:toPath];
	[super rename:from to:to];
}

- (void)deleteFile:(NSString *)path
{
	[super deleteFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:path]];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	[super deleteDirectory:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:dirPath]];
}

- (void)uploadFile:(NSString *)localPath
{
	[super uploadFile: localPath
             toFile: [myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{	
	return [super uploadFile:localPath
					  toFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:remotePath]
		checkRemoteExistence:flag
					delegate:delegate];
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	return [self uploadFile:localPath
					 toFile:remotePath
	   checkRemoteExistence:NO
				   delegate:delegate];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{	
	return [super uploadFromData:data
						  toFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:remotePath]
			checkRemoteExistence:flag
						delegate:delegate];
}

- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate
{
	return [super resumeUploadFromData:data
								toFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:remotePath]
							fileOffset:offset
							  delegate:delegate];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[super downloadFile:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:remotePath]
			toDirectory:dirPath
			  overwrite:flag];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	[self downloadFile:remotePath
		   toDirectory:dirPath
			 overwrite:YES];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	[super contentsOfDirectory:[[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:dirPath]];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no path specified");
	NSString *dir = [[NSString stringWithFormat:@"/%@", [[self URL] user]] stringByAppendingPathComponent:[path stringByDeletingLastPathComponent]];
	
	//if we pass in a relative path (such as xxx.tif), then the last path is @"", with a length of 0, so we need to add the current directory
	//according to docs, passing "/" to stringByDeletingLastPathComponent will return "/", conserving a 1 size
	
	if (!dir || [dir length] == 0)
	{
		path = [[self currentDirectory] stringByAppendingPathComponent:path];
	}
	
	[self queueFileCheck:path];
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processFileCheckingQueue];
}

- (void)connection:(id <CKConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
{
	if (_flags.fileCheck) {
		NSString *name = [_fileCheckInFlight lastPathComponent];
		NSEnumerator *e = [contents objectEnumerator];
		NSDictionary *cur;
		BOOL foundFile = NO;
		
		while (cur = [e nextObject]) 
		{
			if ([[cur objectForKey:cxFilenameKey] isEqualToString:name]) 
			{
				[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:YES error:nil];
				foundFile = YES;
				break;
			}
		}
		if (!foundFile)
		{
			[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:NO error:nil];
		}
	}
	[self dequeueFileCheck];
	[_fileCheckInFlight autorelease];
	_fileCheckInFlight = nil;
	[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0.0];
}

@end


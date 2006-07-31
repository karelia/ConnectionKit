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

#import "DotMacConnection.h"
#import "AbstractConnection.h"
#import "AbstractConnectionProtocol.h"
#import "DAVRequest.h"
#import "DAVDirectoryContentsRequest.h"
#import "DAVCreateDirectoryRequest.h"
#import "DAVUploadFileRequest.h"
#import "DAVDeleteRequest.h"
#import "DAVFileDownloadRequest.h"
#import "DAVResponse.h"
#import "DAVDirectoryContentsResponse.h"
#import "DAVCreateDirectoryResponse.h"
#import "DAVUploadFileResponse.h"
#import "DAVDeleteResponse.h"
#import "DAVFileDownloadResponse.h"
#import "NSData+Connection.h"
#import <Security/Security.h>
#import "ConnectionThreadManager.h"

@interface NSString (DotMac)
- (NSString *)stringByDeletingFirstPathComponent;
@end

@interface WebDAVConnection (DotMac)
- (void)processResponse:(DAVResponse *)response;
@end

@implementation DotMacConnection

#pragma mark class methods

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"http://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[DotMacConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @".Mac";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	DotMacConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password
											   error:error];
	return [c autorelease];
}

#pragma mark init methods

- (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password
{
	NSString *accountName = [[NSUserDefaults standardUserDefaults] objectForKey:@"iToolsMember"];
	SecKeychainItemRef item = nil;
	OSStatus theStatus = noErr;
	char *buffer;
	UInt32 passwordLen;
	
	theStatus = SecKeychainFindGenericPassword(NULL,
											   6,
											   "iTools",
											   [accountName length],
											   [accountName UTF8String],
											   &passwordLen,
											   &buffer,
											   &item);
	
	if (noErr == theStatus)
	{
		buffer[passwordLen] = '\0';		// make it a legal C string by appending 0
		if (password)
			*password = [NSString stringWithUTF8String:buffer];
		else
			*password = nil;
		
		*account = accountName;
		return YES;
	}
	return NO;
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)user
		  password:(NSString *)pass
			 error:(NSError **)error
{
	NSString *username = nil;
	NSString *password = nil;

	if (![self getDotMacAccountName:&username password:&password])
	{
		if (error)
		{
			NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
											   code:ConnectionNoUsernameOrPassword
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Failed to retrieve .mac account details", @"No .mac account or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
	}
	
	if (self = [super initWithHost:@"idisk.mac.com" port:@"80" username:username password:password error:error])
	{
		myCurrentDirectory = [[NSString stringWithFormat:@"/%@/", username] retain];
	}
	return self;
}

#pragma mark -
#pragma mark WebDAV Overrides

- (void)processResponse:(DAVResponse *)response
{
	switch (GET_STATE)
	{
		case ConnectionAwaitingDirectoryContentsState:
		{
			DAVDirectoryContentsResponse *dav = (DAVDirectoryContentsResponse *)response;
			NSString *err = nil;
			switch ([dav code])
			{
				case 200:
				case 207: //multi-status
				{
					if (_flags.directoryContents)
					{
						[_forwarder connection:self 
							didReceiveContents:[dav directoryContents]
								   ofDirectory:[[dav path] stringByDeletingFirstPathComponent]];
					}
					break;
				}
				case 404:
				{		
					err = [NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"There is no .Mac access to the directory", @".Mac Directory Contents Error"), [dav path]];
				}
				default: 
				{
					err = @"Unknown Error Occurred";
				}
			}
			if (err)
			{
				if (_flags.error)
				{
					NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithObject:err forKey:NSLocalizedDescriptionKey];
					[ui setObject:[dav className] forKey:@"DAVResponseClass"];
					NSError *error = [NSError errorWithDomain:WebDAVErrorDomain
														 code:[dav code]
													 userInfo:ui];
					[_forwarder connection:self didReceiveError:error];
				}
			}				
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionCreateDirectoryState:
		{
			DAVCreateDirectoryResponse *dav = (DAVCreateDirectoryResponse *)response;
			NSString *err = nil;
			NSMutableDictionary *ui = [NSMutableDictionary dictionary];
			
			switch ([dav code])
			{
				case 201: 
				{
					if (_flags.createDirectory)
					{
						[_forwarder connection:self 
							didCreateDirectory:[[dav directory] stringByDeletingFirstPathComponent]];
					}
					break;
				}
				case 403:
				{		
					err = LocalizedStringInThisBundle(@"The server does not allow the creation of directories at the current location", @".Mac Create Directory Error");
						//we fake the directory exists as this is usually the case if it is the root directory
					[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 405:
				{		
					err = LocalizedStringInThisBundle(@"The directory already exists", @".Mac Create Directory Error");
					[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 409:
				{
					err = LocalizedStringInThisBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @".Mac Create Directory Error");
					break;
				}
				case 415:
				{
					err = LocalizedStringInThisBundle(@"The body of the request is not supported", @".Mac Create Directory Error");
					break;
				}
				case 507:
				{
					err = LocalizedStringInThisBundle(@"Insufficient storage space available", @".Mac Create Directory Error");
					break;
				}
				default: 
				{
					err = LocalizedStringInThisBundle(@"An unknown error occured", @".Mac Create Directory Error");
					break;
				}
			}
			if (err)
			{
				if (_flags.error)
				{
					[ui setObject:err forKey:NSLocalizedDescriptionKey];
					[ui setObject:[dav className] forKey:@"DAVResponseClass"];
					[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
					[ui setObject:[dav directory] forKey:@"directory"];
					NSError *error = [NSError errorWithDomain:WebDAVErrorDomain
														 code:[dav code]
													 userInfo:ui];
					[_forwarder connection:self didReceiveError:error];
				}
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionUploadingFileState:
		{
			DAVUploadFileResponse *dav = (DAVUploadFileResponse *)response;
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.uploadFinished)
					{
						[_forwarder connection:self
							   uploadDidFinish:[[[self currentUpload] objectForKey:QueueUploadRemoteFileKey] stringByDeletingFirstPathComponent]];
					}
					break;
				}
				case 409:
				{		
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Parent Folder does not exist", @".Mac File Uploading Error")
																					 forKey:NSLocalizedDescriptionKey];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
					break;
			}
			[self dequeueUpload];
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteFileState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.deleteFile)
					{
						[_forwarder connection:self 
								 didDeleteFile:[[self currentDeletion] stringByDeletingFirstPathComponent]];
					}
					break;
				}
				default:
				{
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionary];
						[ui setObject:[NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete file", @".Mac file deletion error"), [[self currentDeletion] stringByDeletingFirstPathComponent]] forKey:NSLocalizedDescriptionKey];
						[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
			}
			[self dequeueDeletion];
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteDirectoryState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.deleteDirectory)
					{
						[_forwarder connection:self 
							didDeleteDirectory:[[self currentDeletion] stringByDeletingFirstPathComponent]];
					}
					break;
				}
				default:
				{
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionary];
						[ui setObject:[NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete directory", @".Mac Directory Deletion Error"), [[self currentDeletion] stringByDeletingFirstPathComponent]] 
							   forKey:NSLocalizedDescriptionKey];
						[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
			}
			[self dequeueDeletion];
			[self setState:ConnectionIdleState];
			break;
		}
		default: [super processResponse:response];
	}
}

- (void)stream:(id<OutputStream>)stream readBytesOfLength:(unsigned)length
{
	if (length == 0) return;
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		NSString *download = [[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] stringByDeletingFirstPathComponent];
		bytesTransferred += length;
		if (_flags.downloadPercent)
		{
			if (bytesToTransfer > 0) // intel gives a crash for div by 0
			{
				int percent = (bytesTransferred * 100) / bytesToTransfer;
				[_forwarder connection:self 
							  download:download
						  progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		if (_flags.downloadProgressed)
		{
			[_forwarder connection:self
						  download:download
			  receivedDataOfLength:length];
		}
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	if (length == 0) return;
	if (GET_STATE == ConnectionUploadingFileState)
	{
		if (transferHeaderLength > 0)
		{
			if (length <= transferHeaderLength)
			{
				transferHeaderLength -= length;
			}
			else
			{
				transferHeaderLength = 0;
				length -= transferHeaderLength;
			}
		}
		else
		{
			bytesTransferred += length;
		}
		
		NSString *upload = [[[self currentUpload] objectForKey:QueueUploadRemoteFileKey] stringByDeletingFirstPathComponent];
		if (_flags.uploadPercent)
		{
			if (bytesToTransfer > 0) // intel gives a crash for div by 0
			{
				int percent = (bytesTransferred * 100) / bytesToTransfer;
				[_forwarder connection:self 
								upload:upload
						  progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		if (_flags.uploadProgressed)
		{
			[_forwarder connection:self 
							upload:upload
				  sentDataOfLength:length];
		}
	}
}

#pragma mark -
#pragma mark Protocol Overrides

- (void)changeToDirectory:(NSString *)dirPath
{
	[super changeToDirectory:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:dirPath]];
}

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:[dirPath stringByDeletingFirstPathComponent]];
	}
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:ConnectionIdleState];
}

- (NSString *)currentDirectory
{
	return [[super currentDirectory] stringByDeletingFirstPathComponent];
}

- (NSDictionary *)currentDownload
{
  NSMutableDictionary *returnValue = [NSMutableDictionary dictionaryWithDictionary: [super currentDownload]];
  
  if ([returnValue objectForKey: QueueDownloadRemoteFileKey])
    [returnValue setObject: [[returnValue objectForKey: QueueDownloadRemoteFileKey] stringByDeletingFirstPathComponent]
                    forKey: QueueDownloadRemoteFileKey];
  
  return [NSDictionary dictionaryWithDictionary: returnValue];
}

- (NSDictionary *)currentUpload
{
  NSMutableDictionary *returnValue = [NSMutableDictionary dictionaryWithDictionary: [super currentUpload]];
  
  if ([returnValue objectForKey: QueueUploadRemoteFileKey])
    [returnValue setObject: [[returnValue objectForKey: QueueUploadRemoteFileKey] stringByDeletingFirstPathComponent]
                    forKey: QueueUploadRemoteFileKey];
  
  return [NSDictionary dictionaryWithDictionary: returnValue];
}

- (NSString *)rootDirectory
{
	return [[super rootDirectory] stringByDeletingFirstPathComponent];
}

- (void)createDirectory:(NSString *)dirPath
{
	[super createDirectory:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:dirPath]];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	[super createDirectory:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:dirPath]
			   permissions:permissions];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	[super setPermissions:permissions
				  forFile:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:path]];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSString *from = [[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:fromPath];
	NSString *to = [[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:toPath];
	[super rename:from to:to];
}

- (void)deleteFile:(NSString *)path
{
	[super deleteFile:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:path]];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	[super deleteDirectory:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:dirPath]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[super uploadFile:localPath
			   toFile:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:remotePath]];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[super uploadFromData:data
				   toFile:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:remotePath]];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[super downloadFile:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:remotePath]
			toDirectory:dirPath
			  overwrite:flag];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	[self downloadFile:remotePath
		   toDirectory:dirPath
			 overwrite:YES];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	[super contentsOfDirectory:[[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:dirPath]];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSString *dir = [[NSString stringWithFormat:@"/%@", [self username]] stringByAppendingPathComponent:[path stringByDeletingLastPathComponent]];
	
	//if we pass in a relative path (such as xxx.tif), then the last path is @"", with a length of 0, so we need to add the current directory
	//according to docs, passing "/" to stringByDeletingLastPathComponent will return "/", conserving a 1 size
	
	if (!dir || [dir length] == 0)
	{
		path = [[self currentDirectory] stringByAppendingPathComponent:path];
	}
	
	[self queueFileCheck:path];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processFileCheckingQueue];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
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
				[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:YES];
				foundFile = YES;
				break;
			}
		}
		if (!foundFile)
		{
			[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:NO];
		}
	}
	[self dequeueFileCheck];
	[_fileCheckInFlight autorelease];
	_fileCheckInFlight = nil;
	[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0.0];
}

@end

@implementation NSString (DotMac)

- (NSString *)stringByDeletingFirstPathComponent
{
	NSString *str = self;
	if ([str hasPrefix:@"/"])
		str = [str substringFromIndex:1];
	NSMutableArray *comps = [NSMutableArray arrayWithArray:[str componentsSeparatedByString:@"/"]];
	if ([comps count] > 0) {
		[comps removeObjectAtIndex:0];
	}
	return [@"/" stringByAppendingString:[comps componentsJoinedByString:@"/"]];
}

@end

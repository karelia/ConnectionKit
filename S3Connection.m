/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
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

#import "S3Connection.h"
#import "CKHTTPRequest.h"
#import "NSData+Connection.h"
#import "NSString+Connection.h"
#import "NSCalendarDate+Connection.h"
#import "CKHTTPPutRequest.h"
#import "CKHTTPFileDownloadRequest.h"
#import "CKHTTPResponse.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSFileManager+Connection.h"
#import "KTLog.h"

NSString *S3ErrorDomain = @"S3ErrorDomain";
NSString *S3StorageClassKey = @"S3StorageClassKey";
NSString *S3PathSeparator = @":"; //@"0xKhTmLbOuNdArY";

@implementation S3Connection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"s3://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[S3Connection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"Amazon S3";
}

#pragma mark init methods

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	S3Connection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password
											   error:error];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (!username || [username length] == 0 || !password || [password length] == 0)
	{
		if (error)
		{
			NSError *err = [NSError errorWithDomain:S3ErrorDomain
											   code:ConnectionNoUsernameOrPassword
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Username and Password are required for S3 connections", @"No username or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
	}
	
	// allow for subdomains of s3
	if ([host rangeOfString:@"s3.amazonaws.com"].location == NSNotFound)
	{
		host = @"s3.amazonaws.com";
	}
	
	if (!port || [port isEqualToString:@""])
	{
		port = @"80";
	}
	
	if (self = [super initWithHost:host
                              port:port
                          username:username
                          password:password
							 error:error])
	{
		myCurrentDirectory = @"/";
	}
	return self;
}

- (void)dealloc
{
	[myCurrentDirectory release];
	[myDownloadHandle release];
	
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"s3";
}

- (NSString *)internalRepresentationWithPath:(NSString *)path
{
	NSString *separator = [self propertyForKey:@"S3PathSeparator"];
	if (!separator)
	{
		separator = S3PathSeparator;
	}
	NSString *bucket = [path firstPathComponent];
	NSString *p = [[[path stringByDeletingFirstPathComponent] componentsSeparatedByString:@"/"] componentsJoinedByString:separator];
	return [[@"/" stringByAppendingString:bucket] stringByAppendingPathComponent:p];
}

- (NSString *)externalRepresentationWithPath:(NSString *)internalPath
{
	NSString *separator = [self propertyForKey:@"S3PathSeparator"];
	if (!separator)
	{
		separator = S3PathSeparator;
	}
	NSMutableArray *comps = [[[internalPath componentsSeparatedByString:separator] mutableCopy] autorelease];
	NSString *bucket = [[[comps objectAtIndex:0] retain] autorelease];
	if ([bucket isEqualToString:@""])
	{
		bucket = @"/";
	}
	[comps removeObjectAtIndex:0];
	NSString *p = [comps componentsJoinedByString:@"/"];
	p = [bucket stringByAppendingPathComponent:p]; // doesn't add trailing /
	if ([internalPath hasSuffix:separator])
	{
		p = [p stringByAppendingString:@"/"];
	}
	return p;
}

#pragma mark -
#pragma mark HTTP Overrides

- (void)setAuthenticationWithRequest:(CKHTTPRequest *)request
{
	NSString *method = [request method];
	NSString *md5 = @""; //[[request content] length] > 0 ? [[[request content] md5Digest] base64Encoding] : @"";
	NSString *ct = [request headerForKey:@"Content-Type"];
	NSString *date = [request headerForKey:@"Date"];
		[request setHeader:date forKey:@"Date"];
	
	NSMutableString *auth = [NSMutableString stringWithFormat:@"%@\n%@\n%@\n%@\n", method, md5, ct ? ct : @"", date];
	NSEnumerator *e = [[[[request headers] allKeys] sortedArrayUsingSelector:@selector(compare:)] objectEnumerator];
	NSString *key;
	
	while ((key = [e nextObject]))
	{
		if ([[key lowercaseString] hasPrefix:@"x-amz"])
		{
			[auth appendFormat:@"%@:%@\n", [key lowercaseString], [request headerForKey:key]];
		}
	}
	NSString *uri = [request uri];
	NSRange r = [uri rangeOfString:@"?"];
	if (r.location != NSNotFound)
	{
		uri = [uri substringToIndex:r.location];
	}
	[auth appendString:[uri encodeLegally]];
	
	NSString *sha1 = [[[auth dataUsingEncoding:NSUTF8StringEncoding] sha1HMacWithKey:[self password]] base64Encoding];
	[request setHeader:[NSString stringWithFormat:@"AWS %@:%@", [self username], sha1] forKey:@"Authorization"];
}

- (void)sendErrorWithResponse:(CKHTTPResponse *)response
{
	if (_flags.error)
	{
		NSError *error = nil;
		NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:[response content] 
														 options:NSXMLDocumentTidyXML
														   error:&error];
		NSString *desc = [[[[doc rootElement] nodesForXPath:@"//Error/Message" error:&error] objectAtIndex:0] stringValue];
		NSString *code = [[[[doc rootElement] nodesForXPath:@"//Error/Code" error:&error] objectAtIndex:0] stringValue];
		
		if ([code isEqualToString:@"SignatureDoesNotMatch"])
		{
			[_forwarder connectionDidSendBadPassword:self];
		}
		else
		{
			if (desc)
			{
				NSError *err = [NSError errorWithDomain:S3ErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:desc forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:err];
			}
			else
			{
				KTLog(S3ErrorDomain, KTLogError, @"An unknown error occured:\n%@", response);
			}
		}
	}
}

- (void)processResponse:(CKHTTPResponse *)response
{
	if ([response code] / 100 == 4)
	{
		[self sendErrorWithResponse:response];
		[self setState:ConnectionIdleState];
		return;
	}
	if (!hasSentAuthenticationToDelegate)
	{
		if (_flags.didAuthenticate)
		{
			[_forwarder connection:self didAuthenticateToHost:[self host]];
		}
		hasSentAuthenticationToDelegate = YES;
	}
	switch (GET_STATE)
	{
		case ConnectionAwaitingDirectoryContentsState: 
		{
			if ([response code] / 100 == 2)
			{
				NSError *error = nil;
				NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:[response content] 
																 options:NSXMLDocumentTidyXML
																   error:&error];
				KTLog(ProtocolDomain, KTLogDebug, @"\n%@", [doc XMLStringWithOptions:NSXMLNodePrettyPrint]);
				
				//do the buckets first
				NSXMLElement *cur;
				NSEnumerator *e;
				NSMutableArray *contents = [NSMutableArray array];
				
				if ([myCurrentDirectory isEqualToString:@"/"])
				{
					NSArray *buckets = [[doc rootElement] nodesForXPath:@"//Bucket" error:&error];
					e = [buckets objectEnumerator];
					
					while ((cur = [e nextObject]))
					{
						NSString *name = [[[cur elementsForName:@"Name"] objectAtIndex:0] stringValue];
						NSString *date = [[[cur elementsForName:@"CreationDate"] objectAtIndex:0] stringValue];
						
						NSMutableDictionary *d = [NSMutableDictionary dictionary];
						[d setObject:name forKey:cxFilenameKey];
						[d setObject:[NSCalendarDate calendarDateWithZuluFormat:date] forKey:NSFileCreationDate];
						[d setObject:NSFileTypeDirectory forKey:NSFileType];
						[contents addObject:d];
					}
				}
				
				// contents inside a bucket
				NSArray *bucketContents = [[doc rootElement] nodesForXPath:@"//Contents" error:&error];
				e = [bucketContents objectEnumerator];
				
				NSString *currentPath = [myCurrentDirectory stringByDeletingFirstPathComponent];
				
				while ((cur = [e nextObject]))
				{
					NSString *name = [self externalRepresentationWithPath:[[[cur elementsForName:@"Key"] objectAtIndex:0] stringValue]];
					NSString *date = [[[cur elementsForName:@"LastModified"] objectAtIndex:0] stringValue];
					NSString *size = [[[cur elementsForName:@"Size"] objectAtIndex:0] stringValue];
					NSString *class = [[[cur elementsForName:@"StorageClass"] objectAtIndex:0] stringValue];
					
					NSMutableDictionary *d = [NSMutableDictionary dictionary];
					
					if ([name length] < [currentPath length]) continue; // this is a record from a parent folder
					if ([name rangeOfString:currentPath].location == NSNotFound) continue; // this is an element in a different folder
					
					if ([name hasPrefix:currentPath])
					{
						name = [name substringFromIndex:[currentPath length]];
					}
					
					if ([name rangeOfString:@"/"].location < [name length] - 1) continue; // we are in a subfolder
					
					if ([name hasSuffix:@"/"])
					{
						name = [name substringToIndex:[name length] - 1];
						[d setObject:NSFileTypeDirectory forKey:NSFileType];
					}
					else
					{
						[d setObject:NSFileTypeRegular forKey:NSFileType];
					}
					
					if ([name isEqualToString:@""]) continue; // skip current path name that is returned in results
					
					[d setObject:name forKey:cxFilenameKey];
					[d setObject:[NSCalendarDate calendarDateWithZuluFormat:date] forKey:NSFileModificationDate];
					[d setObject:class forKey:S3StorageClassKey];
					NSScanner *scanner = [NSScanner scannerWithString:size];
					long long filesize;
					[scanner scanLongLong:&filesize];
					[d setObject:[NSNumber numberWithLongLong:filesize] forKey:NSFileSize];
					[contents addObject:d];
				}
				[self cacheDirectory:myCurrentDirectory withContents:contents];
				
				if (_flags.directoryContents)
				{
					[_forwarder connection:self didReceiveContents:contents ofDirectory:[self externalRepresentationWithPath:myCurrentDirectory]];
				}
			}
			break;
		}
		case ConnectionUploadingFileState:
		{
			CKInternalTransferRecord *upload = [self currentUpload];
			
			if (_flags.uploadFinished)
			{
				[_forwarder connection:self uploadDidFinish:[upload remotePath]];
			}
			
			if ([upload delegateRespondsToTransferDidFinish])
			{
				[[upload delegate] transferDidFinish:[upload delegate]];
			}
			
			[self dequeueUpload];
			
			break;
		}
		case ConnectionDeleteFileState:
		{
			if (_flags.deleteFile)
			{
				[_forwarder connection:self didDeleteFile:[self currentDeletion]];
			}
			[self dequeueDeletion];
			break;
		}
		case ConnectionDeleteDirectoryState:
		{
			if (_flags.deleteDirectory)
			{
				[_forwarder connection:self didDeleteDirectory:[self currentDeletion]];
			}
			[self dequeueDeletion];
			break;
		}
		case ConnectionCreateDirectoryState:
		{
			if (_flags.createDirectory)
			{
				[_forwarder connection:self didCreateDirectory:[self externalRepresentationWithPath:[[response request] uri]]];
			}
		}
	}
	[self setState:ConnectionIdleState];
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		if (bytesToTransfer == 0)
		{
			NSDictionary *headers = [CKHTTPResponse headersWithData:myResponseBuffer];
			NSString *length = [headers objectForKey:@"Content-Length"];
			if (length)
			{
				NSScanner *scanner = [NSScanner scannerWithString:length];
				long long daBytes = 0;
				[scanner scanLongLong:&daBytes];
				bytesToTransfer = daBytes;
				
				NSDictionary *download = [self currentDownload];
				NSFileManager *fm = [NSFileManager defaultManager];
				BOOL isDir;
				if ([fm fileExistsAtPath:[download objectForKey:QueueDownloadDestinationFileKey] isDirectory:&isDir] && !isDir)
				{
					[fm removeFileAtPath:[download objectForKey:QueueDownloadDestinationFileKey] handler:nil];
				}
				[fm createFileAtPath:[download objectForKey:QueueDownloadDestinationFileKey]
							contents:nil
						  attributes:nil];
				[myDownloadHandle release];
				myDownloadHandle = [[NSFileHandle fileHandleForWritingAtPath:[download objectForKey:QueueDownloadDestinationFileKey]] retain];
				
				// file data starts after the header
				NSRange headerRange = [myResponseBuffer rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
				NSString *header = [[myResponseBuffer subdataWithRange:NSMakeRange(0, headerRange.location)] descriptionAsUTF8String];
				
				if ([self transcript])
				{
					[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n\n", header] 
																			  attributes:[AbstractConnection receivedAttributes]] autorelease]];
				}
				
				unsigned start = headerRange.location + headerRange.length;
				unsigned len = [myResponseBuffer length] - start;
				NSData *fileData = [myResponseBuffer subdataWithRange:NSMakeRange(start,len)];
				[myDownloadHandle writeData:fileData];
				[myResponseBuffer setLength:0];
				
				bytesTransferred += [fileData length];
				
				if (_flags.downloadProgressed)
				{
					[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] receivedDataOfLength:[fileData length]];
				}
				
				if (_flags.downloadPercent)
				{
					int percent = (100 * bytesTransferred) / bytesToTransfer;
					[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] progressedTo:[NSNumber numberWithInt:percent]];
				}
			}
		}
		else  //add the data at the end of the file
		{
			[myDownloadHandle writeData:data];
			[myResponseBuffer setLength:0]; 
			bytesTransferred += [data length];
			
			if (_flags.downloadProgressed)
			{
				[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] receivedDataOfLength:[data length]];
			}
			
			if (_flags.downloadPercent)
			{
				int percent = (100 * bytesTransferred) / bytesToTransfer;
				[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		
		//check for completion, if the file is really small, then the transfer might be complete on the first pass
		//through this method, so check for completion everytime
		//
		if (bytesTransferred >= bytesToTransfer)  //sometimes more data is received than required (i assume on small size file)
		{
			[myDownloadHandle closeFile];
			[myDownloadHandle release];
			myDownloadHandle = nil;
			
			if (_flags.downloadFinished)
			{
				[_forwarder connection:self downloadDidFinish:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey]];
			}
			[myCurrentRequest release];
			myCurrentRequest = nil;
			[self dequeueDownload];
			[self setState:ConnectionIdleState];
		}
		return NO;
	}
	return YES;
}

- (void)initiatingNewRequest:(CKHTTPRequest *)req withPacket:(NSData *)packet
{
	// if we are uploading or downloading set up the transfer sizes
	if (GET_STATE == ConnectionUploadingFileState)
	{
		transferHeaderLength = [req headerLength];
		bytesToTransfer = [packet length] - transferHeaderLength;
		bytesTransferred = 0;
		
		CKInternalTransferRecord *upload = [self currentUpload];
		
		if (_flags.didBeginUpload)
		{
			[_forwarder connection:self uploadDidBegin:[upload remotePath]];
		}
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload delegate]];
		}
	}
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		bytesToTransfer = 0;
		bytesTransferred = 0;
		
		CKInternalTransferRecord *download = [self currentDownload];
		
		if (_flags.didBeginDownload)
		{
			[_forwarder connection:self downloadDidBegin:[download remotePath]];
		}
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download delegate]];
		}
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	[super stream:stream sentBytesOfLength:length]; // call http
	if (length == 0) return;
	if (GET_STATE == ConnectionUploadingFileState)
	{
		CKInternalTransferRecord *upload = [self currentUpload];
		
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
		
		if (bytesToTransfer > 0)
		{
			int percent = (100 * bytesTransferred) / bytesToTransfer;
			
			if (percent != myLastPercent)
			{
				if (_flags.uploadPercent)
				{
					[_forwarder connection:self 
									upload:[upload remotePath]
							  progressedTo:[NSNumber numberWithInt:percent]];
				}
				if ([upload delegateRespondsToTransferProgressedTo])
				{
					[[upload delegate] transfer:[upload delegate] progressedTo:[NSNumber numberWithInt:percent]];
				}
				myLastPercent = percent;
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
			[[upload delegate] transfer:[upload delegate] transferredDataOfLength:length];
		}
	}
}


#pragma mark -
#pragma mark Connection Overrides

- (void)s3DidChangeToDirectory:(NSString *)dirPath
{
	if (![dirPath hasSuffix:@"/"])
	{
		dirPath = [dirPath stringByAppendingString:@"/"];
	}
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:dirPath];
	}
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:ConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DidChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects: dirPath, nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionChangedDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

- (NSString *)rootDirectory
{
	return @"/";
}

- (void)createDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	if (![dirPath hasSuffix:@"/"])
	{
		dirPath = [dirPath stringByAppendingString:@"/"];
	}
	
	if ([[dirPath componentsSeparatedByString:@"/"] count] > 3) // 1 - first slash, 2 - bucket, 3 - trailing slash
	{
		dirPath = [self internalRepresentationWithPath:dirPath];
	}
	else
	{
		// we are creating a bucket, so remove the trailing /
		dirPath = [dirPath substringToIndex:[dirPath length] - 1];
	}
		
	CKHTTPRequest *req = [[CKHTTPRequest alloc] initWithMethod:@"PUT" uri:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[req release];
	[self queueCommand:cmd];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	//we don't support setting permissions
	[self createDirectory:dirPath];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
		
	CKHTTPRequest *req = [[[CKHTTPRequest alloc] initWithMethod:@"DELETE" 
															uri:[self internalRepresentationWithPath:path]] autorelease];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:path];
	[self queueCommand:cmd];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
		
	CKHTTPRequest *req = [[[CKHTTPRequest alloc] initWithMethod:@"DELETE" 
															uri:[self internalRepresentationWithPath:dirPath]] autorelease];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:dirPath];
	[self queueCommand:cmd];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:flag delegate:nil];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	CKTransferRecord *rec = [CKTransferRecord recordWithName:remotePath size:[[NSFileManager defaultManager] sizeOfPath:localPath]];
	CKHTTPPutRequest *req = [CKHTTPPutRequest putRequestWithContentsOfFile:localPath 
																	   uri:[self internalRepresentationWithPath:remotePath]];
	[req setHeader:@"public-read" forKey:@"x-amz-acl"];
	
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:rec
																		userInfo:nil];
	[rec setUpload:YES];
	
	[self queueUpload:upload];
	[self queueCommand:cmd];
	
	return rec;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	// we don't support upload resumption
	[self uploadFile:localPath];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	[self uploadFile:localPath toFile:remotePath];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	NSString *thePath = [NSString stringWithFormat:@"/%@/%@", [remotePath firstPathComponent], [remotePath stringByDeletingFirstPathComponent]];
	CKHTTPPutRequest *req = [CKHTTPPutRequest putRequestWithData:data filename:[remotePath lastPathComponent] uri:thePath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
	[attribs setObject:data forKey:QueueUploadLocalDataKey];
	[attribs setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	[self queueUpload:attribs];
	[self queueCommand:cmd];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	// we don't support checking remote existence
	[self uploadFromData:data toFile:remotePath];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	// we don't support upload resumption
	[self uploadFromData:data toFile:remotePath];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	NSString *thePath = [NSString stringWithFormat:@"/%@/%@", [remotePath firstPathComponent], [remotePath stringByDeletingFirstPathComponent]];
	CKHTTPFileDownloadRequest *r = [CKHTTPFileDownloadRequest downloadRemotePath:thePath to:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:r
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
	[attribs setObject:remotePath forKey:QueueDownloadRemoteFileKey];
	[attribs setObject:[dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]] forKey:QueueDownloadDestinationFileKey];
	[self queueDownload:attribs];
	[self queueCommand:cmd];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (void)s3DirectoryContents:(NSString *)dir
{
	NSString *theDir = dir != nil ? dir : myCurrentDirectory;

	NSString *uri = [NSString stringWithFormat:@"/%@?max-keys=1000", [theDir firstPathComponent]];
	CKHTTPRequest *r = [[CKHTTPRequest alloc] initWithMethod:@"GET" uri:uri];
	[myCurrentRequest autorelease];
	myCurrentRequest = r;
	[self sendCommand:r];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DirectoryContents:)
													  target:self
												   arguments:[NSArray array]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DirectoryContents:)
													  target:self
												   arguments:[NSArray arrayWithObject:[self internalRepresentationWithPath:dirPath]]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[_forwarder connection:self didReceiveContents:cachedContents ofDirectory:dirPath];
	}
}

@end

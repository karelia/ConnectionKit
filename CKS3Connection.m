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

#import "CKS3Connection.h"
#import "CKHTTPRequest.h"
#import "CKConnectionThreadManager.h"
#import "NSData+Connection.h"
#import "NSString+Connection.h"
#import "NSCalendarDate+Connection.h"
#import "CKHTTPPutRequest.h"
#import "CKHTTPFileDownloadRequest.h"
#import "CKHTTPResponse.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSFileManager+Connection.h"
#import "CKConnectionProtocol.h"


NSString *S3ErrorDomain = @"S3ErrorDomain";
NSString *S3StorageClassKey = @"S3StorageClassKey";
NSString *S3PathSeparator = @":";


@implementation CKS3Connection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	//Register all URL Schemes and the protocol.
	NSEnumerator *URLSchemeEnumerator = [[self URLSchemes] objectEnumerator];
	NSString *URLScheme;
	while ((URLScheme = [URLSchemeEnumerator nextObject]))
		[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forProtocol:[self protocol] URLScheme:URLScheme];	
	
    [pool release];
}

+ (CKProtocol)protocol
{
	return CKAmazonS3Protocol;
}

+ (NSArray *)URLSchemes { return [NSArray arrayWithObjects:@"s3", @"http", nil]; }

#pragma mark init methods

- (id)initWithRequest:(CKConnectionRequest *)request delegate:(id)delegate
{     
    // allow for subdomains of s3
	if ([[[request URL] host] rangeOfString:@"s3.amazonaws.com"].location == NSNotFound)
	{
		NSURL *URL = [[NSURL alloc] initWithScheme:@"http" host:@"s3.amazonaws.com" path:nil];
        CKMutableConnectionRequest *newRequest = [request mutableCopy];
        [newRequest setURL:URL];
        [URL release];
        
        self = [super initWithRequest:newRequest];
        [newRequest release];
	}
    else
    {
        self = [super initWithRequest:request];
    }
	
    
	if (self)
	{
		incompleteDirectoryContents = [[NSMutableArray array] retain];
		incompleteKeyNames = [[NSMutableArray array] retain];
		myCurrentDirectory = @"/";
	}
    
    
	return self;
}

- (void)dealloc
{
	[incompleteDirectoryContents release];
	[incompleteKeyNames release];
	[myCurrentDirectory release];
	[myDownloadHandle release];
    [_currentCredential release];
	[_currentAuthenticationChallenge release];
    
	[super dealloc];
}

- (NSString *)standardizePath:(NSString *)unstandardPath
{
	if (![unstandardPath hasPrefix:@"/"])
		unstandardPath = [@"/" stringByAppendingString:unstandardPath];
	return unstandardPath;
}
- (NSString *)fixPathToBeDirectoryPath:(NSString *)dirPath
{
	if (![dirPath hasSuffix:@"/"])
		dirPath = [dirPath stringByAppendingString:@"/"];
	return [self standardizePath:dirPath];
}
- (NSString *)fixPathToBeFilePath:(NSString *)filePath
{
	if ([filePath hasSuffix:@"/"])
		filePath = [filePath substringToIndex:[filePath length] - 1];
	return [self standardizePath:filePath];
}

#pragma mark -
#pragma mark HTTP Overrides

- (void)setAuthenticationWithRequest:(CKHTTPRequest *)request
{
	// S3 needs decent credentials to operate
    NSAssert(_currentCredential, @"S3 requires credentials to operate");
    NSAssert([_currentCredential user], @"S3 connection has no access key ID");
    NSAssert([_currentCredential persistence] == NSURLCredentialPersistenceNone, @"S3 passwords cannot be persisted");
    NSAssert([_currentCredential password], @"S3 connection has no secret key");
    
    
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
	
	NSString *sha1 = [[[auth dataUsingEncoding:NSUTF8StringEncoding] sha1HMacWithKey:[_currentCredential password]] base64Encoding];
	[request setHeader:[NSString stringWithFormat:@"AWS %@:%@", [_currentCredential user], sha1] forKey:@"Authorization"];
}

- (void)processResponse:(CKHTTPResponse *)response
{
	NSError *error = nil;
	if ([response code] >= 400 && [response code] < 500)
	{
		NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:[response content] 
														 options:NSXMLDocumentTidyXML
														   error:&error];
		NSString *desc = [[[[doc rootElement] nodesForXPath:@"//Error/Message" error:&error] objectAtIndex:0] stringValue];
		NSString *code = [[[[doc rootElement] nodesForXPath:@"//Error/Code" error:&error] objectAtIndex:0] stringValue];
		[doc release];
		
		if ([code isEqualToString:@"SignatureDoesNotMatch"])
		{
			// TODO: Send a fresh authentication request and try again
		}
		else
		{
			if (desc)
				error = [NSError errorWithDomain:S3ErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:desc forKey:NSLocalizedDescriptionKey]];
			else
				KTLog(S3ErrorDomain, KTLogError, @"An unknown error occured:\n%@", response);
		}
	}
	
	switch (GET_STATE)
	{
		case CKConnectionAwaitingDirectoryContentsState: 
		{
			if ([response code] / 100 == 2)
			{
				NSError *error = nil;
				NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithData:[response content] 
																 options:NSXMLDocumentTidyXML
																   error:&error] autorelease];
				KTLog(CKProtocolDomain, KTLogDebug, @"\n%@", [doc XMLStringWithOptions:NSXMLNodePrettyPrint]);
				
				//do the buckets first
				NSXMLElement *cur;
				NSEnumerator *e;
				NSMutableArray *contents = [NSMutableArray array];
				
				BOOL isTruncated = NO;
				NSArray *isTruncatedNodes = [[doc rootElement] nodesForXPath:@"//IsTruncated" error:&error];
				if ([isTruncatedNodes count] > 0)
				{
					NSXMLNode *isTruncatedNode = [isTruncatedNodes objectAtIndex:0];
					NSString *isTruncatedValue = [isTruncatedNode stringValue];
					isTruncated = [isTruncatedValue isEqualToString:@"true"];
				}
								
				if ([myCurrentDirectory isEqualToString:@"/"])
				{
					NSArray *buckets = [[doc rootElement] nodesForXPath:@"//Bucket" error:&error];
					e = [buckets objectEnumerator];
					
					while ((cur = [e nextObject]))
					{
						NSString *name = [[[cur elementsForName:@"Name"] objectAtIndex:0] stringValue];
						NSString *date = [[[cur elementsForName:@"CreationDate"] objectAtIndex:0] stringValue];
						
						CKDirectoryListingItem *item = [CKDirectoryListingItem directoryListingItem];
						[item setFilename:name];
						[item setModificationDate:[NSCalendarDate calendarDateWithZuluFormat:date]];
						[item setFileType:NSFileTypeDirectory];
						[contents addObject:item];
					}
				}
				
				// contents inside a bucket
				NSArray *bucketContents = [[doc rootElement] nodesForXPath:@"//Contents" error:&error];
				e = [bucketContents objectEnumerator];
				
				NSString *currentPath = [myCurrentDirectory stringByDeletingFirstPathComponent];
				
				NSMutableArray *keyNames = [NSMutableArray arrayWithArray:incompleteKeyNames];
				while ((cur = [e nextObject]))
				{
					NSString *rawKeyName = [[[cur elementsForName:@"Key"] objectAtIndex:0] stringValue];
					NSString *name = [self standardizePath:rawKeyName];

					if ([name length] < [currentPath length]) continue; // this is a record from a parent folder
					if ([name rangeOfString:currentPath].location == NSNotFound) continue; // this is an element in a different folder
					
					if ([name hasPrefix:currentPath])
						name = [name substringFromIndex:[currentPath length]];
					
					/*We receive _all_ directory contents at once, so even when we ask for /brianamerige, we get /brianamerige/wp-admin/page.php, for example. Consequently, when currentpath is /wp-admin, we are only looking for things immediately inside /wp-admin. To achieve this, we only keep _one_ of each of the same first path components.
					 */
					if ([keyNames containsObject:[name firstPathComponent]])
						continue;
					[keyNames addObject:[name firstPathComponent]];
					
					if (![[name firstPathComponent] isEqualToString:[name lastPathComponent]])
					{
						//We have /wp-admin/page.php while we're only trying to list /wp-admin
						name = [[name firstPathComponent] stringByAppendingString:@"/"];
					}
					
					NSString *date = [[[cur elementsForName:@"LastModified"] objectAtIndex:0] stringValue];
					NSString *size = [[[cur elementsForName:@"Size"] objectAtIndex:0] stringValue];
					NSString *class = [[[cur elementsForName:@"StorageClass"] objectAtIndex:0] stringValue];
					
					CKDirectoryListingItem *item = [CKDirectoryListingItem directoryListingItem];
					
					if ([name hasSuffix:@"/"])
					{
						name = [name substringToIndex:[name length] - 1];
						[item setFileType:NSFileTypeDirectory];
					}
					else
					{
						[item setFileType:NSFileTypeRegular];
					}
					
					if ([name isEqualToString:@""]) continue; // skip current path name that is returned in results
					
					[item setFilename:name];
					[item setModificationDate:[NSCalendarDate calendarDateWithZuluFormat:date]];
					[item setProperty:class forKey:S3StorageClassKey];
					NSScanner *scanner = [NSScanner scannerWithString:size];
					long long filesize;
					[scanner scanLongLong:&filesize];
					[item setSize:[NSNumber numberWithLongLong:filesize]];
					[contents addObject:item];
				}
				
				if (isTruncated)
				{
					//Keep the contents for the next time around
					[incompleteDirectoryContents addObjectsFromArray:contents];
					[incompleteKeyNames addObjectsFromArray:keyNames];
					
					//We aren't done yet. There are more keys to be listed in this 'directory'
					NSString *bucketName = [myCurrentDirectory firstPathComponent];
					NSString *prefixString = @"";
					if ([bucketName length] > 1)
					{
						NSString *subpath = [myCurrentDirectory substringFromIndex:[bucketName length] + 2];
						if ([subpath length] > 0)
							prefixString = [NSString stringWithFormat:@"?prefix=%@", subpath];
					}
					
					if ([prefixString length] == 0)
						prefixString = @"?"; //If we have no prefix, we need the ? to be /brianamerige?marker=bleh
					else
						prefixString = [prefixString stringByAppendingString:@"&"]; //If we do have a prefix, we need the & to be /brianameige?prefix=dir/&marker=bleh
					
					NSString *lastKeyName = [[[[bucketContents lastObject] elementsForName:@"Key"] objectAtIndex:0] stringValue];
					NSString *markerString = [NSString stringWithFormat:@"marker=%@", lastKeyName];
					
					NSString *uri = [NSString stringWithFormat:@"/%@%@%@", bucketName, prefixString, markerString];
					CKHTTPRequest *request = [[CKHTTPRequest alloc] initWithMethod:@"GET" uri:[uri encodeLegallyForS3]];
					[myCurrentRequest autorelease];
					myCurrentRequest = request;
					[self sendCommand:request];					
					return; //Don't break. We are not idle yet, so we can't set CKConnectionIdleState as we do at the bottom of the method.
				}
				
				[contents addObjectsFromArray:incompleteDirectoryContents];
				[incompleteDirectoryContents removeAllObjects];
				[incompleteKeyNames removeAllObjects];
				
				[self cacheDirectory:myCurrentDirectory withContents:contents];
				
				//We use fixPathToBeFilePath to strip the / from the end –– we don't traditionally have this in the last path component externally.
				[[self client] connectionDidReceiveContents:contents ofDirectory:[self fixPathToBeFilePath:myCurrentDirectory] error:error];
			}
			break;
		}
		case CKConnectionUploadingFileState:
		{
			CKInternalTransferRecord *upload = [[self currentUpload] retain];
			[self dequeueUpload];
			
			[[self client] uploadDidFinish:[upload remotePath] error:error];
            
			if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload delegate] error:error];
			
			[upload release];
			
			break;
		}
		case CKConnectionDownloadingFileState:
		{
			CKInternalTransferRecord *downloadInfo = [[self currentDownload] retain];
			[self dequeueDownload];
			
			CKTransferRecord *record = (CKTransferRecord *)[downloadInfo userInfo];
			[[self client] downloadDidFinish:[record remotePath] error:nil];
			
			if ([downloadInfo delegateRespondsToTransferDidFinish])
				[[downloadInfo delegate] transferDidFinish:[downloadInfo userInfo] error:nil];
			
			[downloadInfo release];
			break;
		}
		case CKConnectionDeleteFileState:
		{
			[[self client] connectionDidDeleteFile:[self currentDeletion] error:error];
			
			[self dequeueDeletion];
			break;
		}
		case CKConnectionDeleteDirectoryState:
		{
			[[self client] connectionDidDeleteDirectory:[self currentDeletion] error:error];
			[self dequeueDeletion];
			break;
		}
		case CKConnectionCreateDirectoryState:
		{
			[[self client] connectionDidCreateDirectory:[self fixPathToBeDirectoryPath:[[response request] uri]] error:error];
			break;
		}
		case CKConnectionAwaitingRenameState:
		{
			[[self client] connectionDidRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1] error:error];
			[_fileRenames removeObjectAtIndex:0];
			[_fileRenames removeObjectAtIndex:0];			
			break;
		}
		case CKConnectionRenameFromState:
		{
			[self setState:CKConnectionRenameToState];
			return;
		}
		default:
			break;
	}
	
	[self setState:CKConnectionIdleState];
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	if (GET_STATE == CKConnectionDownloadingFileState)
	{
		if (bytesToTransfer == 0)
		{
			NSDictionary *headers = [CKHTTPResponse headersWithData:myResponseBuffer];
			NSString *length = [headers objectForKey:@"Content-Length"];
			if (length > 0)
			{
				NSScanner *scanner = [NSScanner scannerWithString:length];
				long long daBytes = 0;
				[scanner scanLongLong:&daBytes];
				bytesToTransfer = daBytes;
				
				CKTransferRecord *record = (CKTransferRecord *)[[self currentDownload] userInfo];
				NSFileManager *fm = [NSFileManager defaultManager];
				BOOL isDir;
				if ([fm fileExistsAtPath:[record localPath] isDirectory:&isDir] && !isDir)
				{
					[fm removeFileAtPath:[record localPath] handler:nil];
				}
				[fm createFileAtPath:[record localPath]
							contents:nil
						  attributes:nil];
				[myDownloadHandle release];
				myDownloadHandle = [[NSFileHandle fileHandleForWritingAtPath:[record localPath]] retain];
				
				// file data starts after the header
				NSRange headerRange = [myResponseBuffer rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
				NSString *header = [[myResponseBuffer subdataWithRange:NSMakeRange(0, headerRange.location)] descriptionAsUTF8String];
				
				[[self client] appendLine:header toTranscript:CKTranscriptReceived];
				
				
				unsigned start = headerRange.location + headerRange.length;
				unsigned len = [myResponseBuffer length] - start;
				NSData *fileData = [myResponseBuffer subdataWithRange:NSMakeRange(start,len)];
				[myDownloadHandle writeData:fileData];
				[myResponseBuffer setLength:0];
				
				bytesTransferred += [fileData length];
				
				[[self client] download:[record remotePath] didReceiveDataOfLength:[fileData length]];
				
				
				int percent = (bytesToTransfer == 0) ? 0 : (100 * bytesTransferred) / bytesToTransfer;
				[[self client] download:[record remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
			}
		}
		else  //add the data at the end of the file
		{
			[myDownloadHandle writeData:data];
			[myResponseBuffer setLength:0]; 
			bytesTransferred += [data length];
			
			CKInternalTransferRecord *downloadInfo = [self currentDownload];
			CKTransferRecord *record = (CKTransferRecord *)[downloadInfo userInfo];
			
			[[self client] download:[record remotePath] didReceiveDataOfLength:[data length]];
			
			if ([downloadInfo delegateRespondsToTransferTransferredData])
			{
				[[downloadInfo delegate] transfer:record transferredDataOfLength:[data length]];
			}
			
            int percent = (100 * bytesTransferred) / bytesToTransfer;
			[[self client] download:[record remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
			
			if ([downloadInfo delegateRespondsToTransferProgressedTo])
			{
				int percent = (100 * bytesTransferred) / bytesToTransfer;
				[[downloadInfo delegate] transfer:record progressedTo:[NSNumber numberWithInt:percent]];
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
			
			return YES;
		}
		return NO;
	}
	return YES;
}

- (void)initiatingNewRequest:(CKHTTPRequest *)req withPacket:(NSData *)packet
{
	// if we are uploading or downloading set up the transfer sizes
	if (GET_STATE == CKConnectionUploadingFileState)
	{
		transferHeaderLength = [req headerLength];
		bytesToTransfer = [packet length] - transferHeaderLength;
		bytesTransferred = 0;
		
		CKInternalTransferRecord *upload = [self currentUpload];
		
		[[self client] uploadDidBegin:[upload remotePath]];
		
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload delegate]];
		}
	}
	if (GET_STATE == CKConnectionDownloadingFileState)
	{
		bytesToTransfer = 0;
		bytesTransferred = 0;
		
		CKInternalTransferRecord *download = [self currentDownload];
		
		[[self client] downloadDidBegin:[download remotePath]];
		
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
	if (GET_STATE == CKConnectionUploadingFileState)
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
				[[self client] upload:[upload remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
                
				if ([upload delegateRespondsToTransferProgressedTo])
				{
					[[upload delegate] transfer:[upload delegate] progressedTo:[NSNumber numberWithInt:percent]];
				}
				myLastPercent = percent;
			}
		}
		
        [[self client] upload:[upload remotePath] didSendDataOfLength:length];
		
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
	
	[[self client] connectionDidChangeToDirectory:dirPath error:nil];
	
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:CKConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DidChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects: dirPath, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionChangedDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (NSString *)currentDirectory
{
	//We use fixPathToBeFilePath to strip the / from the end –– we don't traditionally have this in the last path component externally.
	return [self fixPathToBeFilePath:myCurrentDirectory];
}

- (NSString *)rootDirectory
{
	return @"/";
}

- (void)createDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	if (![dirPath hasSuffix:@"/"])
		dirPath = [dirPath stringByAppendingString:@"/"]; //Trailing slash indicates it's a directory.
	
	if ([[dirPath componentsSeparatedByString:@"/"] count] < 3)
	{
		// we are creating a bucket, so remove the trailing /
		dirPath = [dirPath substringToIndex:[dirPath length] - 1];
	}
		
	CKHTTPRequest *req = [[CKHTTPRequest alloc] initWithMethod:@"PUT" uri:[dirPath encodeLegallyForS3]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCreateDirectoryState
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
- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	/* 
	 IMPORTANT NOTES ABOUT RENAMING/MOVING ON S3:
	 Renaming (Moving) in the sense that we have in FTP/SFTP/WebDAV is not possible with Amazon S3 at the moment. This current implementation is a temporary workaround until a RENAME or MOVE command is implemented into the API by Amazon.
	 
	 What we're doing here is really copying the fromPath to the toPath (with the COPY command), and then deleting fromPath. 
	 
	 Worth noting, if you're intending on renaming a directory, you must call -recursivelyRenameS3Directory:to: which is implemented and handled by CKAbstractQueueConnection. You need to do this because renaming a directory in the fashion this method implements will not bring the directory's children over with it. You have been warned!
	 */
	
	CKHTTPRequest *copyRequest = [CKHTTPRequest requestWithMethod:@"PUT" uri:[toPath encodeLegallyForS3]];
	[copyRequest setHeader:[fromPath encodeLegallyForS3] forKey:@"x-amz-copy-source"];
	CKConnectionCommand *copyCommand = [CKConnectionCommand command:copyRequest
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionRenameFromState
											  dependant:nil
											   userInfo:nil];
	CKHTTPRequest *deleteRequest = [CKHTTPRequest requestWithMethod:@"DELETE" uri:[fromPath encodeLegallyForS3]];
	CKConnectionCommand *deleteCommand = [CKConnectionCommand command:deleteRequest
													   awaitState:CKConnectionRenameToState
														sentState:CKConnectionAwaitingRenameState
														dependant:copyCommand
														 userInfo:nil];
	[self queueRename:fromPath];
	[self queueRename:toPath];
	[self queueCommand:copyCommand];	
	[self queueCommand:deleteCommand];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
		
	CKHTTPRequest *req = [[[CKHTTPRequest alloc] initWithMethod:@"DELETE" 
															uri:[[self fixPathToBeFilePath:path] encodeLegallyForS3]] autorelease];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:path];
	[self queueCommand:cmd];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	CKHTTPRequest *req = [[[CKHTTPRequest alloc] initWithMethod:@"DELETE" 
															uri:[[self fixPathToBeDirectoryPath:dirPath] encodeLegallyForS3]] autorelease];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:dirPath];
	[self queueCommand:cmd];
}

- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	CKTransferRecord *rec = [CKTransferRecord uploadRecordForConnection:self
														sourceLocalPath:localPath
												  destinationRemotePath:remotePath
																   size:[[NSFileManager defaultManager] sizeOfPath:localPath] 
															isDirectory:NO];
	CKHTTPPutRequest *req = [CKHTTPPutRequest putRequestWithContentsOfFile:localPath 
																	   uri:[[self fixPathToBeFilePath:remotePath] encodeLegallyForS3]];
	[req setHeader:@"public-read" forKey:@"x-amz-acl"];
	
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:(delegate) ? delegate : rec
																		userInfo:nil];
	[self queueUpload:upload];
	[self queueCommand:cmd];
	
	return rec;
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	remotePath = [self fixPathToBeFilePath:remotePath];
	CKHTTPPutRequest *req = [CKHTTPPutRequest putRequestWithData:data filename:[remotePath lastPathComponent] uri:[remotePath encodeLegallyForS3]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:nil 
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:nil
																		userInfo:nil];
	
	[self queueUpload:upload];	
	[self queueCommand:cmd];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	NSString *fixedRemotePath = [self fixPathToBeFilePath:remotePath];
	NSString *localPath = [dirPath stringByAppendingPathComponent:[fixedRemotePath lastPathComponent]];
	
	if (!flag && [[NSFileManager defaultManager] fileExistsAtPath:localPath])
	{
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  LocalizedStringInConnectionKitBundle(@"Local File already exists", @"FTP download error"), NSLocalizedDescriptionKey,
                                  remotePath, NSFilePathErrorKey, nil];
        NSError *error = [NSError errorWithDomain:S3ErrorDomain code:S3DownloadFileExists userInfo:userInfo];
        [[self client] connectionDidReceiveError:error];
		
		return nil;
	}
	
	CKTransferRecord *record = [CKTransferRecord downloadRecordForConnection:self
															sourceRemotePath:fixedRemotePath
														destinationLocalPath:localPath
																		size:0 
																 isDirectory:NO];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:0
																			remote:fixedRemotePath
																		  delegate:(delegate) ? delegate : record
																		  userInfo:record];
	[self queueDownload:download];
	
	CKHTTPFileDownloadRequest *r = [CKHTTPFileDownloadRequest downloadRemotePath:fixedRemotePath to:dirPath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:r
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	return record;
}

- (void)s3DirectoryContents:(NSString *)dir
{
	NSString *theDir = dir != nil ? dir : myCurrentDirectory;
	
	NSString *bucketName = [theDir firstPathComponent];
	NSString *prefixString = @"";
	if ([bucketName length] > 1)
	{
		NSString *subpath = [theDir substringFromIndex:[bucketName length] + 2];
		if ([subpath length] > 0)
			prefixString = [NSString stringWithFormat:@"?prefix=%@", subpath];
	}

	NSString *uri = [NSString stringWithFormat:@"/%@%@", bucketName, prefixString];
	CKHTTPRequest *r = [[CKHTTPRequest alloc] initWithMethod:@"GET" uri:[uri encodeLegallyForS3]];
	[myCurrentRequest autorelease];
	myCurrentRequest = r;
	[self sendCommand:r];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DirectoryContents:)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv 
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[[self client] connectionDidReceiveContents:cachedContents ofDirectory:[self standardizePath:dirPath] error:nil];
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CKDoesNotRefreshCachedListings"])
		{
			return;
		}		
	}		
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(s3DirectoryContents:)
													  target:self
												   arguments:[NSArray arrayWithObject:[self fixPathToBeDirectoryPath:dirPath]]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv 
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
#pragma mark Authentication
- (void)threadedConnect
{
	[myCurrentDirectory release];
	myCurrentDirectory = [[NSString alloc] initWithString:@"/"];
	
	// Request authentication before connecting
    _currentAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:nil
                                                                                 proposedCredential:nil
                                                                               previousFailureCount:0
                                                                                    failureResponse:nil
                                                                                              error:nil
                                                                                             sender:self];
    
    [[self client] connectionDidReceiveAuthenticationChallenge:_currentAuthenticationChallenge];
}

/*  CKHTTPConnection implements the -cancel and -continueWithCredential methods for us in a perfectly
 *  decent manner, so don't bother overriding them.
 */

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge != _currentAuthenticationChallenge)	return;
	[_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
    
    _currentCredential = [credential retain];
    
    // Continue on with connecting
    [super threadedConnect];
}

@end
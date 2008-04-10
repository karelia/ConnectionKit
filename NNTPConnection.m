//
//  NNTPConnection.m
//  FTPConnection
//
//  Created by Greg Hulands on 6/12/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "NNTPConnection.h"

NSString *NNTPErrorDomain = @"NNTPErrorDomain";

NSString *NNTPFirstMessageKey = @"NNTPFirstMessageKey";
NSString *NNTPLastMessageKey = @"NNTPLastMessageKey";
NSString *NNTPCanPostToGroupKey = @"NNTPCanPostToGroupKey";

@interface NSFileManager (NNTPGroupParsing)

+ (NSArray *)attributedNewsGroupsFromListing:(NSString *)listing;

@end

@interface NNTPConnection (Private)

- (void)parseCommand:(NSString *)command;
- (void)receiveNewsGroupsListing;

@end

@implementation NNTPConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"119", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"news://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	NSDictionary *url2 = [NSDictionary dictionaryWithObjectsAndKeys:@"usenet://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	NSDictionary *url3 = [NSDictionary dictionaryWithObjectsAndKeys:@"nntp://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[NNTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, url2, url3, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"NNTP";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	return [[[NNTPConnection alloc] initWithHost:host
											port:port
										username:username
										password:password] autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password]) {
		_inputBuffer = [[NSMutableString alloc] init];
		_newsflags.isSlave = NO;
	}
	return self;
}

- (void)dealloc
{
	[_inputBuffer release];
	[_currentNewsGroup release];
	
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"nntp";
}

- (void)processReceivedData:(NSData *)data
{
	NSRange newLinePosition;
	
	NSString *str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	[_inputBuffer appendString:str];
				
	while ((newLinePosition=[_inputBuffer rangeOfString:@"\r\n"]).location != NSNotFound ||
		   (newLinePosition=[_inputBuffer rangeOfString:@"\n"]).location != NSNotFound)
	{
		NSString *cmd = [_inputBuffer substringToIndex:newLinePosition.location];
		[_inputBuffer deleteCharactersInRange:NSMakeRange(0,newLinePosition.location+newLinePosition.length)]; // delete the parsed part
		[self parseCommand:cmd]; // parse first line of the buffer
	}
}

- (void)sendCommand:(NSString *)cmd
{
	KTLog(ProtocolDomain, KTLogDebug, @">> %@", cmd);
	
	NSString *formattedCommand = [NSString stringWithFormat:@"%@\r\n", cmd];
	
	[self appendToTranscript:[[[NSAttributedString alloc] initWithString:formattedCommand
															  attributes:[AbstractConnection sentAttributes]] autorelease]];
	
	[self sendData:[formattedCommand dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark -
#pragma mark State Machine

- (void)parseCommand:(NSString *)command
{
	NSScanner *scanner = [NSScanner scannerWithString:command];
	int code;
	[scanner scanInt:&code];
	
	[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", command] 
															  attributes:[AbstractConnection receivedAttributes]] autorelease]];
	KTLog(ProtocolDomain, KTLogDebug, @"<<# %@", command);	/// use <<# to help find commands
	
	switch (code) {
#pragma mark -
#pragma mark 100 Series Codes
		case 100: {
			
		} break;
		case 199: {
			
		} break;
#pragma mark -
#pragma mark 200 Series Codes
		case 200: {
			if (GET_STATE == ConnectionNotConnectedState) {
				_newsflags.canPost = YES;
				if (_flags.didConnect)
					[_forwarder connection:self didConnectToHost:[self host]];
				[self setState:ConnectionIdleState];
			}
		} break;
		case 201: {
			if (GET_STATE == ConnectionNotConnectedState) {
				_newsflags.canPost = NO;
				if (_flags.didConnect)
					[_forwarder connection:self didConnectToHost:[self host]];
				[self setState:ConnectionIdleState];
			}
		} break;
		case 202: {
			if (GET_STATE == ConnectionNotConnectedState) {
				_newsflags.isSlave = YES;
				if (_flags.didConnect)
					[_forwarder connection:self didConnectToHost:[self host]];
				[self setState:ConnectionIdleState];
			}
		} break;
		case 205: {
			if (_flags.didDisconnect)
				[_forwarder connection:self didDisconnectFromHost:[self host]];
			[self setState:ConnectionNotConnectedState];
		} break;
		case 211: {
			
		} break;
		case 215: {
			if (GET_STATE == ConnectionAwaitingDirectoryContentsState) {
				[self receiveNewsGroupsListing];
				[self setState:ConnectionIdleState];
			}
		} break;
		case 220: {
			
		} break;
		case 222: {
			
		} break;
		case 223: {
			if (GET_STATE == ConnectionAwaitingDirectoryContentsState) {
				[self receiveNewsGroupsListing];
				[self setState:ConnectionIdleState];
			}
		} break;
		case 231: {
			
		} break;
		case 235: {
			
		} break;
		case 240: {
			
		} break;
#pragma mark -
#pragma mark 300 Series Codes
		case 335: {
			
		} break;
		case 340: {
			
		} break;
#pragma mark -
#pragma mark 400 Series Codes
		case 400: {
			
		} break;
		case 411: {
			
		} break;
		case 412: {
			
		} break;
		case 420: {
			
		} break;
		case 421: {
			
		} break;
		case 422: {
			
		} break;
		case 423: {
			
		} break;
		case 430: {
			
		} break;
		case 435: {
			
		} break;
		case 436: {
			
		} break;
		case 437: {
			
		} break;
		case 440: {
			
		} break;
		case 441: {
			
		} break;
#pragma mark -
#pragma mark 500 Series Codes
		case 500: {
			
		} break;
		case 501: {
			
		} break;
		case 502: {
			if (GET_STATE == ConnectionNotConnectedState) {
				NSError *err = [NSError errorWithDomain:NNTPErrorDomain
												   code:502
											   userInfo:nil];
				if (_flags.error)
					[_forwarder connection:self didReceiveError:err];
			}
		} break;
		case 503: {
			
		} break;
	}
}

- (void)changeToDirectory:(NSString *)dirPath
{
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"GROUP %@", dirPath]
									   awaitState:ConnectionIdleState
										sentState:ConnectionChangedDirectoryState
										dependant:nil
										 userInfo:nil]];
}

- (NSString *)currentDirectory
{
	return _currentNewsGroup;
}

- (NSString *)rootDirectory
{
	return @"";
}

- (void)createDirectory:(NSString *)dirPath
{
	
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)deleteFile:(NSString *)path
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)uploadFile:(NSString *)localPath
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	if (_flags.error) {
		NSError *err = [NSError errorWithDomain:NNTPErrorDomain
										   code:500
									   userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"New server does not implement %@", NSStringFromSelector(_cmd)]
																			forKey:NSLocalizedDescriptionKey]];
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (void)cancelTransfer
{
	
}

- (void)cancelAll
{
	
}

- (void)directoryContents
{
	[self queueCommand:[ConnectionCommand command:@"LIST -a"
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	[self queueCommand:[ConnectionCommand command:@"LIST -a"
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
}

#pragma mark -
#pragma mark Helper Utilities

- (void)receiveNewsGroupsListing
{
	//consume everything the dot (.)
	BOOL atEnd = NO;
				NSMutableString *groupsListing = [NSMutableString string];
				NSRange newLinePosition;
				NSAutoreleasePool *pool;
				long groupCount = 0;
				NSMutableString *tempGroups = [NSMutableString string];
				
				while (atEnd == NO) {
					pool = [[NSAutoreleasePool alloc] init];
					
					NSData *data = [self availableData];
					NSString *str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
					[_inputBuffer appendString:str];
					[str release];
					
					while ((newLinePosition=[_inputBuffer rangeOfString:@"\r\n"]).location != NSNotFound ||
						   (newLinePosition=[_inputBuffer rangeOfString:@"\n"]).location != NSNotFound)
					{
						NSString *line = [_inputBuffer substringToIndex:newLinePosition.location + newLinePosition.length];
						[_inputBuffer deleteCharactersInRange:NSMakeRange(0,newLinePosition.location+newLinePosition.length)]; // delete the parsed part
						[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", line]
																				  attributes:[AbstractConnection dataAttributes]] autorelease]];
						KTLog(ProtocolDomain, KTLogError, @"%@", line);
						if ([line rangeOfString:@"."].location == 0)
							atEnd = YES;
						else {
							[tempGroups appendString:line];
							[groupsListing appendString:line];
						}
						
						if (groupCount % 500 == 1) {
							if (_flags.directoryContentsStreamed)
								[_forwarder connection:self
									didReceiveContents:[NSFileManager attributedNewsGroupsFromListing:tempGroups]
										   ofDirectory:@""
											moreComing:YES];
							[tempGroups deleteCharactersInRange:NSMakeRange(0,[tempGroups length])];
						}
						
						groupCount++;
					}
					
					[pool release];
				}
				//complete the streaming before the complete directory contents
				if (_flags.directoryContentsStreamed)
					[_forwarder connection:self
						didReceiveContents:[NSFileManager attributedNewsGroupsFromListing:tempGroups]
							   ofDirectory:@""
								moreComing:NO];
				if (_flags.directoryContents)
					[_forwarder connection:self 
						didReceiveContents:[NSFileManager attributedNewsGroupsFromListing:groupsListing] 
							   ofDirectory:@""];
}

@end

@implementation NSFileManager (NNTPGroupParsing)

+ (NSArray *)attributedNewsGroupsFromListing:(NSString *)line
{
	NSMutableArray *groups = [NSMutableArray array];
	NSArray *lines;
	
	NSRange rn = [line rangeOfString:@"\r\n"];
	if (rn.location == NSNotFound)
	{
		rn = [line rangeOfString:@"\n"];
		if (rn.location == NSNotFound)
		{
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain
												 code:ConnectionErrorParsingDirectoryListing
											 userInfo:[NSDictionary dictionaryWithObject:@"Error parsing directory listing" forKey:NSLocalizedDescriptionKey]];
			
			KTLog(ParsingDomain, KTLogError, @"Could not determine line endings, try refreshing directory");
			@throw error;
			return nil;
		}
		else
			lines = [line componentsSeparatedByString:@"\n"];
	}
	else
		lines = [line componentsSeparatedByString:@"\r\n"];
	
	NSEnumerator *e = [lines objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSArray *bits = [cur componentsSeparatedByString:@" "];
		if ([bits count] != 4) continue;
		NSString *group =  [bits objectAtIndex:0];
		NSString *last = [bits objectAtIndex:1];
		NSString *first = [bits objectAtIndex:2];
		NSString *canPost = [bits objectAtIndex:3];
		BOOL cp = [[canPost lowercaseString] isEqualToString:@"y"];
		long long l, f;
		NSScanner *scanner = [NSScanner scannerWithString:last];
		[scanner scanLongLong:&l];
		scanner = [NSScanner scannerWithString:first];
		[scanner scanLongLong:&f];
		
		NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
		
		[attribs setObject:NSFileTypeDirectory forKey:NSFileType];
		[attribs setObject:group forKey:cxFilenameKey];
		[attribs setObject:[NSNumber numberWithLongLong:l] forKey:NNTPLastMessageKey];
		[attribs setObject:[NSNumber numberWithLongLong:f] forKey:NNTPFirstMessageKey];
		[attribs setObject:[NSNumber numberWithLongLong:abs(l-f)] forKey:NSFileSize];
		[attribs setObject:[NSNumber numberWithBool:cp] forKey:NNTPCanPostToGroupKey];
		[groups addObject:attribs];
	}
	return groups;
}

@end
//
//  CKTransferRecord.m
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKTransferRecord.h"
#import <Connection/NSString+Connection.h>

NSString *CKTransferRecordProgressChangedNotification = @"CKTransferRecordProgressChangedNotification";

@implementation CKTransferRecord

+ (void)initialize
{
	[CKTransferRecord setKeys:[NSArray arrayWithObject:@"progress"] triggerChangeNotificationsForDependentKey:@"nameWithProgress"];
}

+ (id)recordWithName:(NSString *)name size:(unsigned long long)size
{
	return [[[CKTransferRecord alloc] initWithName:name size:size] autorelease];
}

- (id)initWithName:(NSString *)name size:(unsigned long long)size
{
	if ((self = [super init])) 
	{
		myName = [name copy];
		mySize = size;
		myContents = [[NSMutableArray array] retain];
		myProperties = [[NSMutableDictionary dictionary] retain];
		myError = nil;
		myProgress = 0;
	}
	return self;
}

- (void)dealloc
{
	[myName release];
	[myContents makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	[myContents release];
	[myProperties release];
	[myError release];
	[super dealloc];
}

- (void)setUpload:(BOOL)flag
{
	isUpload = YES;
}

- (BOOL)isUpload
{
	return isUpload;
}

- (void)cancel:(id)sender
{
	if ([self connection])
	{
		[[self connection] cancelTransfer];
	}
}

- (void)setName:(NSString *)name
{
	if (myName != name)
	{
		[self willChangeValueForKey:@"name"];
		[myName autorelease];
		myName = [name copy];
		[self didChangeValueForKey:@"name"];
	}
}

- (NSString *)name
{
	return myName;
}

- (void)setSize:(unsigned long long)size
{
	[self willChangeValueForKey:@"progress"];
	mySize = size;
	[self didChangeValueForKey:@"progress"];
}

- (unsigned long long)size
{
	unsigned long long size = mySize;
	NSEnumerator *e = [myContents objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur respondsToSelector:@selector(size)])
		{
			size += [cur size];
		}
		else
		{
			NSLog(@"CKTransferRecord content object does not have 'size'");		// work around bogus children?
		}
	}
	return size;
}

- (unsigned long long)transferred
{
	if ([self isDirectory]) 
	{
		unsigned long long rem = 0;
		NSEnumerator *e = [myContents objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject])) 
		{
			rem += [cur transferred];
		}
		return rem;
	}
	if (myProgress == -1) //if we have an error return it as if we transferred the lot of it
	{
		return mySize;
	}
	return myTransferred;
}

- (double)speed
{
	if ([self isDirectory]) 
	{
		if (myTransferStartTime == 0.0)
		{
			myTransferStartTime = [NSDate timeIntervalSinceReferenceDate];
		}
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
		if (myLastDirectorySpeedUpdate == 0.0 || now - myLastDirectorySpeedUpdate >= 1.0)
		{
			myLastDirectorySpeedUpdate = now;
			NSTimeInterval elapsedTime = now - myTransferStartTime;
			unsigned long long transferred = [self transferred];
			[self willChangeValueForKey:@"speed"];
			mySpeed = transferred / elapsedTime;
			[self didChangeValueForKey:@"speed"];
		}
	}
	return mySpeed;
}

- (void)setSpeed:(double)speed
{
	if (speed != mySpeed)
	{
		[self willChangeValueForKey:@"speed"];
		mySpeed = speed;
		[self didChangeValueForKey:@"speed"];
	}
}

- (void)forceAnimationUpdate
{
	int i;
	for (i = 1; i <= 4; i++)
	{
		[self willChangeValueForKey:@"progress"];
		myProgress = i * 25;
		[self didChangeValueForKey:@"progress"];
		[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification
															object:self];
	}
}

- (void)setProgress:(int)progress
{
	if (myProgress != progress)
	{
		if (progress == 100 && myProgress == 1)
		{
			[self forceAnimationUpdate];
			return;
		}
		[self willChangeValueForKey:@"progress"];
		myProgress = progress;
		[self didChangeValueForKey:@"progress"];
		[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification
															object:self];
	}
}

- (NSNumber *)progress
{
	// Check if self of descendents have an error, so we can show that error.
	if ([self hasError])
	{
		return [NSNumber numberWithInt:-1];
	}
	
	if ([self isDirectory]) 
	{
		//get the real transfer progress of the whole directory
		unsigned long long size = [self size];
		unsigned long long transferred = [self transferred];
		if (size == 0) size = 1;
		int percent = (int)((transferred / (size * 1.0)) * 100);
		return [NSNumber numberWithInt:percent];
	}
	return [NSNumber numberWithInt:myProgress];
}

- (BOOL)problemsTransferringCountingErrors:(int *)outErrors successes:(int *)outSuccesses
{
	if ([self isLeaf])
	{
		if (myError != nil)
		{
			(*outErrors)++;
		}
		else
		{
			(*outSuccesses)++;
		}
	}
	else
	{
		// check children for errors
		NSEnumerator *e = [myContents objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			(void) [cur problemsTransferringCountingErrors:outErrors successes:outSuccesses];
		}
	}
	return (*outErrors > 0);	// return if there were any problems
}

- (BOOL)hasError
{
	BOOL ret = (myError != nil);
	if (!ret)
	{
		// check children for errors
		NSEnumerator *e = [myContents objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur hasError])
			{
				ret = YES;
				break;
			}
		}
	}
	return ret;
}

- (NSError *)error
{
	return myError;
}

- (void)setError:(NSError *)error
{
	if (error != myError)
	{
		[self willChangeValueForKey:@"progress"]; // we use this because we return -1 on an error
		[myError autorelease];
		myError = [error retain];
		[self didChangeValueForKey:@"progress"];
		[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification
															object:self];
	}
}

- (id <AbstractConnectionProtocol>)connection
{
	return myConnection;
}

- (void)setConnection:(id <AbstractConnectionProtocol>)connection
{
	if (connection != myConnection)
	{
		myConnection = connection;
	}
}

- (BOOL)isDirectory
{
	return [myContents count] > 0;
}

- (void)setParent:(CKTransferRecord *)parent
{
	myParent = parent;
}

- (CKTransferRecord *)parent
{
	return myParent;
}

- (CKTransferRecord *)root
{
	if (myParent)
	{
		return [myParent root];
	}
	return self;
}

- (NSString *)path
{
	if (myParent == nil)
		return [NSString stringWithFormat:@"/%@", myName];
	return [NSString stringWithFormat:@"%@/%@", [myParent path], myName];
}

- (void)addContent:(CKTransferRecord *)record
{
	[self willChangeValueForKey:@"contents"];
	[myContents addObject:record];
	[record setParent:self];
	[self didChangeValueForKey:@"contents"];
}

- (NSArray *)contents
{
	return myContents;
}

- (void)appendToDescription:(NSMutableString *)str indentation:(unsigned)indent
{
	int i;
	for (i = 0; i < indent; i++)
	{
		[str appendString:@"\t"];
	}	
	[str appendFormat:@"\t%@", myName];
	if ([self isDirectory])
	{
		[str appendString:@"/"];
	}
	[str appendFormat:@"\t(%lld of %lld bytes - %@%%)\n", [self transferred], [self size], [self progress]];

	NSEnumerator *e = [myContents objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		[cur appendToDescription:str indentation:indent+1];
	}
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self appendToDescription:str indentation:0];
	return str;
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[myProperties setObject:property forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [myProperties objectForKey:key];
}

// keep NSDictionary accessor compatible so we can move over internal use of this class

- (void)setObject:(id)object forKey:(id)key
{
	[self setProperty:object forKey:key];
}

- (id)objectForKey:(id)key
{
	return [self propertyForKey:key];
}

#pragma mark -
#pragma mark Connection Transfer Delegate

- (void)transferDidBegin:(CKTransferRecord *)transfer
{
	[self setProgress:0];
	myTransferred = 0;
	myIntermediateTransferred = 0;
	myLastTransferTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length
{
	myTransferred += length;
	myIntermediateTransferred += length;
	
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval difference = now - myLastTransferTime;
	
	if (difference > 1.0 || myTransferred == mySize)
	{
		[self willChangeValueForKey:@"speed"];
		if (myTransferred == mySize)
		{
			[self setSpeed:0.0];
		}
		else
		{
			[self setSpeed:((double)myIntermediateTransferred) / difference];
		}
		myIntermediateTransferred = 0;
		myLastTransferTime = now;
		[self didChangeValueForKey:@"speed"];
	}
}

- (void)transfer:(CKTransferRecord *)transfer progressedTo:(NSNumber *)percent
{
	[self setProgress:[percent intValue]];
}

- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error
{
	[self setError:error];
}

- (void)transferDidFinish:(CKTransferRecord *)transfer
{
	[self setProgress:100];
}

#pragma mark -
#pragma mark Recursive File Transfer Methods

+ (CKTransferRecord *)rootRecordWithPath:(NSString *)path
{
	CKTransferRecord *cur;
	
	cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
	path = [path stringByDeletingFirstPathComponent];
	CKTransferRecord *thisNode, *subNode = cur;
	
	while ((![path isEqualToString:@"/"]))
	{
		thisNode = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
		path = [path stringByDeletingFirstPathComponent];
		[subNode addContent:thisNode];
		subNode = thisNode;
	}
	
	return cur;
}

+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forFullPath:(NSString *)path
{
	if ([[record name] isEqualToString:[path firstPathComponent]]) 
	{
		NSEnumerator *e = [[record contents] objectEnumerator];
		CKTransferRecord *cur;
		CKTransferRecord *child;
		
		NSString *newPath = [path stringByDeletingFirstPathComponent2];
		if ([newPath isEqualToString:@""]) return record; //we have our match
		
		while ((cur = [e nextObject])) 
		{
			child = [CKTransferRecord recursiveRecord:cur forFullPath:newPath];
			if (child)
			{
				return child;
			}
		}
	}
	return nil;
}

+ (CKTransferRecord *)recordForFullPath:(NSString *)path withRoot:(CKTransferRecord *)root
{
	return [self recursiveRecord:root forPath:path];
}	

+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forPath:(NSString *)path
{
	if ([[record name] isEqualToString:[path firstPathComponent]]) 
	{
		NSEnumerator *e = [[record contents] objectEnumerator];
		CKTransferRecord *cur;
		CKTransferRecord *child;
		
		NSString *newPath = [path stringByDeletingFirstPathComponent2];
		if ([newPath isEqualToString:@""]) return record; // matched
		
		while ((cur = [e nextObject])) 
		{
			child = [CKTransferRecord recursiveRecord:cur forPath:newPath];
			if (child)
			{
				return child;
			}
		}
	}
	return nil;
}

+ (CKTransferRecord *)recordForPath:(NSString *)path withRoot:(CKTransferRecord *)root
{
	if ([path isEqualToString:@""])
		return root;
	NSEnumerator *e = [[root contents] objectEnumerator];
	CKTransferRecord *cur;
	CKTransferRecord *child;
	
	while (cur = [e nextObject]) 
	{
		child = [self recursiveRecord:cur forPath:path];
		if (child)
		{
			return child;
		}
	}
	return nil;
}

+ (CKTransferRecord *)addFileRecord:(NSString *)file size:(unsigned long long)size withRoot:(CKTransferRecord *)root rootPath:(NSString *)rootPath
{
	NSString *chompedStoragePath = [file substringFromIndex:[rootPath length]];
	NSString *path = [chompedStoragePath stringByDeletingLastPathComponent];
	NSString *filename = [file lastPathComponent];
	
	NSEnumerator *pathCompEnum = [[path componentsSeparatedByString:@"/"] objectEnumerator];
	NSString *builtupPath = [NSString stringWithString:@""];
	NSString *cur;
	CKTransferRecord *rec = nil, *lastRec = root;
	
	while ((cur = [pathCompEnum nextObject]))
	{
		builtupPath = [builtupPath stringByAppendingPathComponent:cur];
		rec = [CKTransferRecord recordForPath:builtupPath withRoot:root];
		if (!rec) 
		{ 
			//create a new record for the path
			rec = [CKTransferRecord recordWithName:[builtupPath lastPathComponent] size:0];
			if (lastRec == nil) 
			{
				//we are at the root
				[root addContent:rec];
			} else 
			{
				[lastRec addContent:rec];
			}
		}
		lastRec = rec;
	}
	//last rec will be the directory to add the file name to
	rec = [CKTransferRecord recordWithName:filename size:size];
	[lastRec addContent:rec];
	return rec;
}

+ (void)mergeRecord:(CKTransferRecord *)record withRoot:(CKTransferRecord *)root
{
	CKTransferRecord *parent = [CKTransferRecord recordForPath:[[record name] stringByDeletingLastPathComponent]
													  withRoot:root];
	[record setName:[[record name] lastPathComponent]];
	[parent addContent:record];
}

+ (CKTransferRecord *)recursiveMergeRecordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	NSString *first = [path firstPathComponent];
	
	if ([[root name] isEqualToString:first])
	{
		CKTransferRecord *child = nil;
		NSEnumerator *e = [[root contents] objectEnumerator];
		CKTransferRecord *cur;
		path = [path stringByDeletingFirstPathComponent];
		
		if ([path isEqualToString:@"/"])
			return root;
		
		while ((cur = [e nextObject]))
		{
			child = [self recursiveMergeRecordWithPath:path root:cur];
			if (child)
				return child;
		}
		
		// if we get here we need to create the record		
		CKTransferRecord *tmp = root;
		while (![path isEqualToString:@"/"])
		{
			cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
			[tmp addContent:cur];
			tmp = cur;
			path = [path stringByDeletingFirstPathComponent];
		}
		return cur;
	}
	return nil;
}

+ (void)mergeTextPathRecord:(CKTransferRecord *)rec withRoot:(CKTransferRecord *)root
{
	CKTransferRecord *parent = [CKTransferRecord recursiveMergeRecordWithPath:[[rec name] stringByDeletingLastPathComponent]
																		 root:root];
	[parent addContent:rec];
	[rec setName:[[rec name] lastPathComponent]];
}

#pragma mark -
#pragma mark NSTreeController support

- (BOOL)isLeaf
{
	return [myContents count] == 0;
}

- (NSDictionary *)nameWithProgress
{
	NSNumber *progress = nil;
	if ([self hasError])
	{
		progress = [NSNumber numberWithInt:-1];
	}
	else
	{
		progress = [self progress];
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:progress, @"progress", [self name], @"name", nil];
}

- (void)setNameWithProgress:(id)notused
{
	; // just for KVO bindings
}

@end

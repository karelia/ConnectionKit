//
//  CKTransferRecord.m
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKTransferRecord.h"
#import <Connection/NSString+Connection.h>

@implementation CKTransferRecord

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
	}
	return self;
}

- (void)dealloc
{
	[myName release];
	[myContents release];
	[myProperties release];
	[super dealloc];
}

- (NSString *)name
{
	return myName;
}

- (unsigned long long)size
{
	unsigned long long size = mySize;
	NSEnumerator *e = [myContents objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		size += [cur size];
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
	if (myProgress == -1) 
	{
		return mySize;
	} 
	else
	{	
		return (mySize * (myProgress / 100.0));
	}
}

- (void)setProgress:(int)progress
{
	myProgress = progress;
}

- (NSNumber *)progress
{
	if ([self isDirectory]) 
	{
		//get the real transfer progress of the whole directory
		unsigned long long size = [self size];
		unsigned long long transferred = [self transferred];
		int percent = (int)((transferred / (size * 1.0)) * 100);
		return [NSNumber numberWithInt:percent];
	}
	return [NSNumber numberWithInt:myProgress];
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

- (NSString *)path
{
	if (myParent == nil)
		return [NSString stringWithFormat:@""];
	return [NSString stringWithFormat:@"%@/%@", [myParent path], myName];
}

- (void)addContent:(CKTransferRecord *)record
{
	[myContents addObject:record];
	[record setParent:self];
}

- (NSArray *)contents
{
	return [NSArray arrayWithArray:myContents];
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
	[str appendString:@"\n"];
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
#pragma mark Recursive File Transfer Methods

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
	NSEnumerator *e = [[root contents] objectEnumerator];
	CKTransferRecord *cur;
	CKTransferRecord *child;
	
	while ((cur = [e nextObject]))
	{
		child = [CKTransferRecord recursiveRecord:cur forFullPath:path];
		if (child)
		{
			return child;
		}
	}
	return nil;
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

@end

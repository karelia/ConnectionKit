/*
 Copyright (c) 2007, Ubermind, Inc
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Ubermind, Inc nor the names of its contributors may be used to 
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
 
 Authored by Greg Hulands <ghulands@mac.com>
 */

#import "CKDirectoryNode.h"
#import "AbstractConnectionProtocol.h"
#import "NSString+Connection.h"
#import "NSNumber+Connection.h"

NSString *CKDirectoryNodeDidRemoveNodesNotification = @"CKDirectoryNodeDidRemoveNodesNotification";

@implementation CKDirectoryNode

- (id)initWithName:(NSString *)name
{
	if ((self != [super init]))
	{
		[self release];
		return nil;
	}
	myName = [name copy];
	myContents = [[NSMutableArray alloc] initWithCapacity:32];
	myProperties = [[NSMutableDictionary alloc] initWithCapacity:32];
	myCachedIcons = [[NSMutableDictionary alloc] initWithCapacity:8];
	// by default we are a directory - this helps with the icons in the popup button for directories above the first directory returned (relative root)
	[self setProperty:NSFileTypeDirectory forKey:NSFileType];
	
	return self;
}

- (void)dealloc
{
	[myName release];
	[myContents makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	[myContents release];
	[myProperties release];
	[myIcon release];
	[myCachedIcons release];
	[myCachedContents release];
	
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	CKDirectoryNode *copy = [[CKDirectoryNode alloc] initWithName:myName];
	
	[copy setParent:myParent];
	[copy setContents:myContents];
	[copy setProperties:myProperties];
	
	return copy;
}

- (BOOL)isEqual:(id)obj
{
	if ([obj isKindOfClass:[CKDirectoryNode class]])
	{
		return [[self path] isEqualToString:[obj path]];
	}
	return NO;
}

- (unsigned)hash
{
	return [[self path] hash];
}

+ (CKDirectoryNode *)nodeWithName:(NSString *)name
{
	return [[[CKDirectoryNode alloc] initWithName:name] autorelease];
}

+ (CKDirectoryNode *)recursiveRecord:(CKDirectoryNode *)record forPath:(NSString *)path
{
	if ([[record name] isEqualToString:[path firstPathComponent]]) 
	{
		NSEnumerator *e = [[record contents] objectEnumerator];
		CKDirectoryNode *cur;
		CKDirectoryNode *child;
		
		NSString *newPath = [path stringByDeletingFirstPathComponent2];
		if ([newPath isEqualToString:@""]) return record; // matched
		
		while ((cur = [e nextObject])) 
		{
			child = [CKDirectoryNode recursiveRecord:cur forPath:newPath];
			if (child)
			{
				return child;
			}
		}
	}
	return nil;
}

+ (CKDirectoryNode *)recordForPath:(NSString *)path withRoot:(CKDirectoryNode *)root
{
	if ([path isEqualToString:@""])
		return root;
	NSEnumerator *e = [[root contents] objectEnumerator];
	CKDirectoryNode *cur;
	CKDirectoryNode *child;
	
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

+ (CKDirectoryNode *)nodeForPath:(NSString *)path withRoot:(CKDirectoryNode *)root
{
	if ([path isEqualToString:@"/"]) return root;
	if ([path isEqualToString:@""]) return root;
	
	return [CKDirectoryNode recordForPath:path withRoot:root];
}

+ (CKDirectoryNode *)addContents:(NSArray *)contents withPath:(NSString *)file withRoot:(CKDirectoryNode *)root
{
	// see if we have a node already for this folder
	CKDirectoryNode *rec = nil, *lastRec = root;
	
	rec = [CKDirectoryNode nodeForPath:file withRoot:root];
	
	if (rec)
	{
		[rec mergeContents:contents];
		return rec;
	}
	
	NSString *path = [file stringByDeletingLastPathComponent];
	NSString *filename = [file lastPathComponent];
	
	NSEnumerator *pathCompEnum = [[path componentsSeparatedByString:@"/"] objectEnumerator];
	NSString *builtupPath = [NSString stringWithString:@""];
	NSString *cur;
	
	
	while ((cur = [pathCompEnum nextObject]))
	{
		builtupPath = [builtupPath stringByAppendingPathComponent:cur];
		rec = [CKDirectoryNode recordForPath:builtupPath withRoot:root];
		if (!rec) 
		{ 
			//create a new record for the path
			rec = [CKDirectoryNode nodeWithName:[builtupPath lastPathComponent]];
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
	rec = [CKDirectoryNode nodeWithName:filename];
	[rec mergeContents:contents];
	[lastRec addContent:rec];
	return rec;
}

- (NSString *)name
{
	return myName;
}

int CKDirectoryContentsSort(id obj1, id obj2, void *context)
{
	CKDirectoryNode *n1 = (CKDirectoryNode *)obj1;
	CKDirectoryNode *n2 = (CKDirectoryNode *)obj2;
	
	return [[n1 name] caseInsensitiveCompare:[n2 name]];
}

- (void)addContent:(CKDirectoryNode *)content
{
	[myContents addObject:content];
	[content setParent:self];
	[myContents sortUsingFunction:CKDirectoryContentsSort context:nil];
}

- (void)addContents:(NSArray *)contents
{
	[myContents addObjectsFromArray:contents];
	[contents makeObjectsPerformSelector:@selector(setParent:) withObject:self];
	[myContents sortUsingFunction:CKDirectoryContentsSort context:nil];
}

- (void)setContents:(NSArray *)contents
{
	[[NSNotificationCenter defaultCenter] postNotificationName:CKDirectoryNodeDidRemoveNodesNotification object:myContents];
	[myContents removeAllObjects];
	[myContents addObjectsFromArray:contents];
	[contents makeObjectsPerformSelector:@selector(setParent:) withObject:self];
	[myContents sortUsingFunction:CKDirectoryContentsSort context:nil];
}

- (BOOL)directory:(NSString *)dir existsIn:(NSArray *)entries
{
	NSEnumerator *e = [entries objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([[cur name] isEqualToString:dir])
		{
			return YES;
		}
	}
	return NO;
}

- (BOOL)entry:(CKDirectoryNode *)entry existsIn:(NSArray *)files
{
    NSEnumerator *e = [files objectEnumerator];
    CKDirectoryNode *cur;
    
    NSString *name = [entry name];
    NSString *type = [entry propertyForKey:NSFileType];
    
    while ((cur = [e nextObject]))
    {        
        if ([[cur name] isEqualToString:name] &&
            [[cur propertyForKey:NSFileType] isEqualToString:type])
        {
            return YES;
        }
    }
    
    return NO;
}

- (void)mergeContents:(NSArray *)contents
{
    NSMutableArray *originals = [NSMutableArray arrayWithArray:myContents];
	NSMutableArray *files = [NSMutableArray array];
	NSEnumerator *e = [myContents objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		if (![cur isDirectory])
		{
			[files addObject:cur];
		}
	}
	
	//remove the files from the contents
	NSMutableSet *filesDeleted = [NSMutableSet setWithArray:files];
	[myContents removeObjectsInArray:files];
	[originals removeObjectsInArray:files];
    
	files = [NSMutableArray array];
	e = [contents objectEnumerator];
	
	while ((cur = [e nextObject]))
	{
		if (![cur isDirectory] || ![self directory:[cur name] existsIn:myContents])
		{
			[files addObject:cur];
		}
	}
	// update with new files
	[myContents addObjectsFromArray:files];
	[files makeObjectsPerformSelector:@selector(setParent:) withObject:self];
	[myContents sortUsingFunction:CKDirectoryContentsSort context:nil];
	[filesDeleted minusSet:[NSSet setWithArray:files]];
	
	if ([filesDeleted count] > 0)
	{
		// need to post the notification so the path is still correct
		[[NSNotificationCenter defaultCenter] postNotificationName:CKDirectoryNodeDidRemoveNodesNotification object:[filesDeleted allObjects]];
		[files makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	}
    
    // remove any folders that have been removed
    files = [NSMutableArray array];
    e = [originals objectEnumerator];
    
    while ((cur = [e nextObject]))
    {
        if (![self entry:cur existsIn:contents])
        {
            [files addObject:cur];
        }
    }
	if ([files count] > 0)
	{
		// need to post the notification so the path is still correct
		[[NSNotificationCenter defaultCenter] postNotificationName:CKDirectoryNodeDidRemoveNodesNotification object:files];
		[files makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
		[myContents removeObjectsInArray:files];
	}
}

- (NSArray *)contents
{
	return myContents;
}

- (unsigned)countIncludingHiddenFiles:(BOOL)flag
{
	if (flag)
	{
		return [myContents count];
	}
	else
	{
		unsigned i, c = 0;
		CKDirectoryNode *cur;
		
		for (i = 0; i < [myContents count]; i++)
		{
			cur = [myContents objectAtIndex:i];
			if (![[cur name] hasPrefix:@"."])
			{
				c++;
			}
		}
		return c;
	}
}

- (NSArray *)contentsIncludingHiddenFiles:(BOOL)flag
{
	if (flag)
	{
		return [NSArray arrayWithArray:myContents];
	}
	else
	{
		NSMutableArray *contents = [NSMutableArray array];
		NSEnumerator *e = [myContents objectEnumerator];
		CKDirectoryNode *cur;
		
		while ((cur = [e nextObject]))
		{
			if (![[cur name] hasPrefix:@"."])
			{
				[contents addObject:cur];
			}
		}
		return contents;
	}
}

- (NSArray *)filteredContentsWithNamesLike:(NSString *)match includeHiddenFiles:(BOOL)flag
{
	NSArray *files = [self contentsIncludingHiddenFiles:flag];
	NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[files count]];
	NSEnumerator *e = [files objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([[cur name] rangeOfString:match options:NSCaseInsensitiveSearch].location != NSNotFound)
		{
			[filtered addObject:cur];
		}
	}
	
	return filtered;
}

- (BOOL)isDirectory
{
	return ([myContents count] > 0 || 
			[[self propertyForKey:NSFileType] isEqualToString:NSFileTypeDirectory] ||
			([[self propertyForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink] && [[self propertyForKey:cxSymbolicLinkTargetKey] hasSuffix:@"/"]));
}

- (BOOL)isFilePackage
{
	return ([self isDirectory] && ![[[self name] pathExtension] isEqualToString:@""]);
}

- (BOOL)isChildOfFilePackage
{
    CKDirectoryNode *parent = [self parent];
    
    while (parent)
    {
        if ([parent isFilePackage])
        {
            return YES;
        }
        parent = [parent parent];
    }
    return NO;
}

- (BOOL)isChildOf:(CKDirectoryNode *)node
{
    CKDirectoryNode *parent = [self parent];
    
    while (parent)
    {
        if (parent == node)
        {
            return YES;
        }
        parent = [parent parent];
    }
    return NO;
}

- (void)setParent:(CKDirectoryNode *)parent
{
	myParent = parent;
}

- (CKDirectoryNode *)parent
{
	return myParent;
}

- (CKDirectoryNode *)root
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
		return myName;
	return [[myParent path] stringByAppendingPathComponent:myName];
}

- (unsigned long long)size
{
	unsigned long long size = [[self propertyForKey:NSFileSize] unsignedLongLongValue];
	NSEnumerator *e = [myContents objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		size += [cur size];
	}
	return size;
}

- (NSString *)kind
{	
	NSString *UTI = [(NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
																	   (CFStringRef)[myName pathExtension],
																	   NULL) autorelease];
	NSString *desc = [(NSString *)UTTypeCopyDescription((CFStringRef)UTI) autorelease];	
	if (!desc && [self isDirectory]) return LocalizedStringInConnectionKitBundle(@"Folder", @"directory kind");
	if (!desc) return LocalizedStringInConnectionKitBundle(@"Document", @"unknown UTI name");
	if ([desc isEqualToString:@"text"]) return LocalizedStringInConnectionKitBundle(@"Plain text document", @"mimic Finder naming conventions");
	
	return desc;
}

- (void)setProperty:(id)prop forKey:(NSString *)key
{
	[myProperties setObject:prop forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [myProperties objectForKey:key];
}

- (void)setProperties:(NSDictionary *)props
{
	[myProperties removeAllObjects];
	[myProperties addEntriesFromDictionary:props];
}

- (NSDictionary *)properties
{
	return myProperties;
}

static NSImage *sFolderIcon = nil;
static NSImage *sSymFolderIcon = nil;
static NSImage *sSymFileIcon = nil;

- (NSImage *)icon
{
	if (myIcon) return myIcon;
	
	NSImage *img = nil;
	
	if ([[self propertyForKey:NSFileType] isEqualToString:NSFileTypeDirectory] &&
		[[self kind] isEqualToString:LocalizedStringInConnectionKitBundle(@"Folder", @"directory kind")]) // this is for document bundles so they get their correct icon
	{
		if (!sFolderIcon)
		{
			sFolderIcon = [[[NSWorkspace sharedWorkspace] iconForFile:@"/tmp"] retain];
		}
		
		img = sFolderIcon;
	}
	else if ([[self propertyForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
	{
		if (!sSymFolderIcon || !sSymFileIcon)
		{
            NSBundle *bndl = [NSBundle bundleForClass:[self class]];
			sSymFolderIcon = [[NSImage alloc] initWithContentsOfFile:[bndl pathForResource:@"symlink_folder" ofType:@"tif"]];
			sSymFileIcon = [[NSImage alloc] initWithContentsOfFile:[bndl pathForResource:@"symlink_file" ofType:@"tif"]];
		}
		NSString *target = [self propertyForKey:cxSymbolicLinkTargetKey];
		
		if ([target characterAtIndex:[target length] - 1] == '/' || [target characterAtIndex:[target length] - 1] == '\\')
			img = sSymFolderIcon;
		else
		{
			NSImage *fileType = [[NSWorkspace sharedWorkspace] iconForFileType:[[self propertyForKey:cxFilenameKey] pathExtension]];
			NSImage *comp = [[NSImage alloc] initWithSize:NSMakeSize(128,128)];
			[fileType setScalesWhenResized:YES];
			[fileType setSize:NSMakeSize(128,128)];
			[comp lockFocus];
			[fileType drawInRect:NSMakeRect(0,0,128,128) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
			[sSymFileIcon drawInRect:NSMakeRect(0,0,128,128) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
			[comp unlockFocus];
			[comp autorelease];
			img = comp;
		}
	}
	// see if we are a command line tool
	else if ([[self propertyForKey:NSFileType] isEqualToString:NSFileTypeRegular] &&
			 [[self propertyForKey:NSFilePosixPermissions] isExecutable] &&
			 (![[self propertyForKey:cxFilenameKey] pathExtension] || [[[self propertyForKey:cxFilenameKey] pathExtension] isEqualToString:@""]))
	{
		img = [[NSWorkspace sharedWorkspace] iconForFileType:@"command"];
	}
	else
	{
		// see if we are an application wrapper and try and see if we are also on this machine and grab its icon
		NSString *filename = [self propertyForKey:cxFilenameKey];
		NSString *ext = [filename pathExtension];
		
		if ([ext isEqualToString:@"app"])
		{
			NSString *path = [[NSWorkspace sharedWorkspace] fullPathForApplication:[filename stringByDeletingPathExtension]];			
			img = [[NSWorkspace sharedWorkspace] iconForFile:path];
		}
	}
	if (!img)
	{
		img = [[NSWorkspace sharedWorkspace] iconForFileType:[[self propertyForKey:cxFilenameKey] pathExtension]];
	}
	
	myIcon = [img retain];
	
	return myIcon;
}

- (NSImage *)iconWithSize:(NSSize)size
{
	NSImage *icon = [myCachedIcons objectForKey:NSStringFromSize(size)];
	
	if (!icon)
	{
		icon = [[self icon] copy];
		[icon setScalesWhenResized:YES];
		[icon setSize:size];
		
		[myCachedIcons setObject:icon forKey:NSStringFromSize(size)];
		[icon release];
	}
	
	return icon;
}

- (void)setCachedContents:(NSData *)contents
{
	[myCachedContents autorelease];
	myCachedContents = [contents retain];
}

- (NSData *)cachedContents
{
	return myCachedContents;
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
	return [self path];
}

- (NSString *)longDescription
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self appendToDescription:str indentation:0];
	return str;
}

@end




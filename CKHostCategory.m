/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
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

#import "CKHostCategory.h"
#import "CKHost.h"

NSString *CKHostCategoryChanged = @"CKHostCategoryChanged";

@interface CKHostCategory (private)
- (void)didChange;
@end

@implementation CKHostCategory

+ (void)initialize	// preferred over +load in most cases
{
	[CKHostCategory setVersion:1];
}

- (id)initWithName:(NSString *)name
{
	if ((self = [super init]))
	{
		myName = [name copy];
		myIsEditable = YES;
		myChildCategories = [[NSMutableArray array] retain];
	}
	return self;
}

- (void)dealloc
{
	[myName release];
	[myChildCategories release];
	[super dealloc];
}

- (id)initWithDictionary:(NSDictionary *)dictionary
{
	if ((self = [super init]))
	{
		myName = [[dictionary objectForKey:@"name"] copy];
		myIsEditable = YES;
		myChildCategories = [[NSMutableArray alloc] init];
		
		NSArray *cats = [dictionary objectForKey:@"categories"];
		NSEnumerator *e = [cats objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			if ([[cur objectForKey:@"class"] isEqualToString:@"category"])
			{
				CKHostCategory *cat = [[CKHostCategory alloc] initWithDictionary:cur];
				[myChildCategories addObject:cat];
				[cat release];
			}
			else
			{
				CKHost *host = [[CKHost alloc] initWithDictionary:cur];
				[myChildCategories addObject:host];
				[host release];
			}
		}
	}
	return self;
}

- (NSDictionary *)plistRepresentation
{
	NSMutableDictionary *plist = [NSMutableDictionary dictionary];
	
	[plist setObject:@"category" forKey:@"class"];
	[plist setObject:[NSNumber numberWithInt:[CKHostCategory version]] forKey:@"version"];
	[plist setObject:myName forKey:@"name"];
	NSMutableArray *cats = [NSMutableArray array];
	NSEnumerator *e = [myChildCategories objectEnumerator];
	id cur;
	
	while ((cur = [e nextObject]))
	{
		[cats addObject:[cur plistRepresentation]];
	}
	[plist setObject:cats forKey:@"categories"];
	
	return plist;
}

- (id)initWithCoder:(NSCoder *)coder
{
	if (self = [super init])
	{
		(void) [coder decodeIntForKey:@"version"];
#pragma unused (version)
		myName = [[coder decodeObjectForKey:@"name"] copy];
		myIsEditable = YES;
		myChildCategories = [[NSMutableArray arrayWithArray:[coder decodeObjectForKey:@"categories"]] retain];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:[CKHostCategory version] forKey:@"version"];
	[coder encodeObject:myName forKey:@"name"];
	[coder encodeObject:myChildCategories forKey:@"categories"];
}

- (NSString *)name
{
	return myName;
}

- (void)setName:(NSString *)name
{
	if (name != myName)
	{
		[myName autorelease];
		myName = [name copy];
		[self didChange];
	}
}

- (void)didChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:CKHostCategoryChanged object:self];
}

- (void)addItem:(id)item
{
	[self willChangeValueForKey:@"childCategories"];
	[myChildCategories addObject:item];
	[item setCategory:self];
	[self didChangeValueForKey:@"childCategories"];
	[self didChange];
}

- (void)insertItem:(id)item atIndex:(unsigned)index
{
	if (index >= [myChildCategories count])
	{
		[self addChildCategory:item];
		return;
	}
	[self willChangeValueForKey:@"childCategories"];
	[myChildCategories insertObject:item atIndex:index];
	[item setCategory:self];
	[self didChangeValueForKey:@"childCategories"];
	[self didChange];
}

- (void)removeItem:(id)item
{
	[self willChangeValueForKey:@"childCategories"];
    [item setCategory:nil];
	[myChildCategories removeObjectIdenticalTo:item];
	[self didChangeValueForKey:@"childCategories"];
	[self didChange];
}

- (void)addChildCategory:(CKHostCategory *)cat
{
	[self addItem:cat];
}

- (void)insertChildCategory:(CKHostCategory *)cat atIndex:(unsigned)index
{
	[self insertItem:cat atIndex:index];
}

- (void)removeChildCategory:(CKHostCategory *)cat
{
	[self removeItem:cat];
}

- (NSArray *)childCategories
{
	return [NSArray arrayWithArray:myChildCategories];
}

- (void)addHost:(CKHost *)host
{
	[self addItem:host];
}

- (void)insertHost:(CKHost *)host atIndex:(unsigned)index
{
	[self insertItem:host atIndex:index];
}

- (void)removeHost:(CKHost *)host
{
	[self removeItem:host];
}

- (NSArray *)hosts
{
	return [NSArray arrayWithArray:myChildCategories];
}

- (void)setCategory:(CKHostCategory *)parent
{
	if (parent != myParentCategory)
	{
		myParentCategory = parent;
		[self didChange];
	}
}

- (CKHostCategory *)category
{
	return myParentCategory;
}

- (BOOL)isChildOf:(CKHostCategory *)cat
{
    CKHostCategory *parent = [self category];
    
    while (parent)
    {
        if (parent == cat)
        {
            return YES;
        }
        parent = [parent category];
    }
    return NO;
}

static NSImage *sFolderImage = nil;

+ (NSImage *)icon
{
	if (!sFolderImage)
	{
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];
		
		//If we're on Leopard, use the Leopard icon. Otherwise we use the Aqua icon.
		BOOL isLeopard = NO;
		SInt32 OSVersion;		
		if (Gestalt(gestaltSystemVersionMinor, &OSVersion) == noErr)
		{
			isLeopard = (OSVersion >= 5);
		}
		NSString *folderIconPath = (isLeopard) ? ([bundle pathForResource:@"LeopardFolder" ofType:@"tiff"]) : ([bundle pathForResource:@"AquaFolder" ofType:@"png"]);
		sFolderImage = [[NSImage alloc] initWithContentsOfFile:folderIconPath];
		[sFolderImage setScalesWhenResized:YES];
		[sFolderImage setSize:NSMakeSize(16.0, 16.0)];
	}
	return sFolderImage;
}

- (NSImage *)icon
{
	return [CKHostCategory icon];
}

- (NSImage *)iconWithSize:(NSSize)size
{
	NSImage *copy = [[self icon] copy];
	[copy setScalesWhenResized:YES];
	[copy setSize:size];
	return [copy autorelease];
}

- (void)setEditable:(BOOL)editableFlag
{
	myIsEditable = editableFlag;
}

- (BOOL)isEditable
{
	return myIsEditable;
}

- (NSArray *)children
{
	return [NSArray arrayWithArray:myChildCategories];
}

- (void)appendToDescription:(NSMutableString *)str indentation:(unsigned)indent
{
	[str appendFormat:@"%@:\n", myName];
	NSEnumerator *e = [myChildCategories objectEnumerator];
	id host;
	
	while ((host = [e nextObject]))
	{
		if ([host isKindOfClass:[CKHost class]])
		{
			int i;
			for (i = 0; i < indent; i++)
			{
				[str appendString:@"\t"];
			}
			[str appendFormat:@"\t%@\n", [host name]];
		}
		else
		{
			[host appendToDescription:str indentation:indent+1];
		}
	}
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self appendToDescription:str indentation:0];
	return str;
}

@end

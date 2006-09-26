//
//  CKHostCategory.m
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHostCategory.h"

NSString *CKHostCategoryChanged = @"CKHostCategoryChanged";

@implementation CKHostCategory

+ (void)load
{
	[CKHostCategory setVersion:1];
}

- (id)initWithName:(NSString *)name
{
	if ((self = [super init]))
	{
		myName = [name copy];
		myChildCategories = [[NSMutableArray array] retain];
		myHosts = [[NSMutableArray array] retain];
	}
	return self;
}

- (void)dealloc
{
	[myName release];
	[myChildCategories release];
	[myHosts release];
	[super dealloc];
}

- (id)initWithCoder:(NSCoder *)coder
{
	if (self = [super init])
	{
		int version = [coder decodeIntForKey:@"version"];
		myName = [[coder decodeObjectForKey:@"name"] copy];
		myChildCategories = [[coder decodeObjectForKey:@"categories"] retain];
		myHosts = [[coder decodeObjectForKey:@"hosts"] retain];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:[CKHostCategory version] forKey:@"version"];
	[coder encodeObject:myName forKey:@"name"];
	[coder encodeObject:myChildCategories forKey:@"categories"];
	[coder encodeObject:myHosts forKey:@"hosts"];
}

- (NSString *)name
{
	return myName;
}

- (void)didChanged
{
	[[NSNotificationCenter defaultCenter] postNotificationName:CKHostCategoryChanged object:self];
}

- (void)addChildCategory:(CKHostCategory *)cat
{
	[myChildCategories addObject:cat];
}

- (void)removeChildCategory:(CKHostCategory *)cat
{
	[myChildCategories removeObject:cat];
}

- (NSArray *)childCategories
{
	return [NSArray arrayWithArray:myChildCategories];
}

- (void)hostChanged:(NSNotification *)n
{
	[self didChange];
}

- (void)addHost:(CKHost *)host
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(hostChanged:)
												 name:CKHostCategoryChanged
											   object:host];
	[myHosts addObject:host];
}

- (void)removeHost:(CKHost *)host
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:CKHostCategoryChanged object:host];
	[myHosts removeObject:host];
}

- (NSArray *)hosts
{
	return [NSArray arrayWithArray:myHosts];
}

static NSImage *sFolderImage = nil;
- (NSImage *)icon
{
	if (!sFolderImage)
	{
		sFolderImage = [[NSImage imageNamed:@"folder"] copy];
		[sFolderImage setScalesWhenResized:YES];
		[sFolderImage setSize:NSMakeSize(16,16)];
	}
	return sFolderImage;
}

- (BOOL)isEditable
{
	return YES;
}

- (id)childAtIndex:(unsigned)index
{
	NSArray *concat = [myChildCategories arrayByAddingObjectsFromArray:myHosts];
	
	return [concat objectAtIndex:index];
}

- (unsigned)count
{
	return [myChildCategories count] + [myHosts count];
}

@end

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

#import "ConnectionRegistry.h"
#import "CKHostCategory.h"
#import "CKBonjourCategory.h"
#import "CKHost.h"
#import "AbstractConnection.h"
#import "CKHostCell.h"

static NSLock *sRegistryLock = nil;
static BOOL sRegistryCanInit = NO;
static ConnectionRegistry *sRegistry = nil;
static NSString *sRegistryDatabase = nil;

NSString *CKRegistryNotification = @"CKRegistryNotification";
NSString *CKRegistryChangedNotification = @"CKRegistryChangedNotification";

@interface ConnectionRegistry (Private)
- (void)otherProcessChanged:(NSNotification *)notification;
- (NSString *)databaseFile;
- (void)changed:(NSNotification *)notification;
@end

@implementation ConnectionRegistry

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	sRegistryLock = [[NSLock alloc] init];
	[pool release];
}

+ (id)sharedRegistry
{
	if (!sRegistry)
	{
		[sRegistryLock lock];
		sRegistryCanInit = YES;
		sRegistry = [[ConnectionRegistry alloc] init];
		sRegistryCanInit = NO;
	}
	return sRegistry;
}

+ (void)setRegistryDatabase:(NSString *)file
{
	[sRegistryDatabase autorelease];
	sRegistryDatabase = [file copy];
}

+ (NSString *)registryDatabase
{
	if (sRegistryDatabase)
	{
		return [[sRegistryDatabase copy] autorelease];
	}
	return [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Preferences"] stringByAppendingPathComponent:@"com.connectionkit.registry"];
}

- (id)init
{
	if (!sRegistryCanInit)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		myLock = [[NSLock alloc] init];
		myCenter = [NSDistributedNotificationCenter defaultCenter];
		myConnections = [[NSMutableArray alloc] init];
		myDraggedItems = [[NSMutableArray alloc] init];
		myDatabaseFile = [[ConnectionRegistry registryDatabase] copy];
		myBonjour = [[CKBonjourCategory alloc] init];
		[myConnections addObject:myBonjour];
		
		[myCenter addObserver:self
					 selector:@selector(otherProcessChanged:)
						 name:CKRegistryNotification
		
					   object:nil];
		NSArray *hosts;
		@try
		{
			hosts = [NSKeyedUnarchiver unarchiveObjectWithFile:[self databaseFile]];
		}
		@catch (NSException *exception) 
		{
			//Registry was corrupted. 
			//We will overwrite the corrupt registry with a fresh one. 
			//Should we inform the user? In any case, log it.
			NSLog(@"Unable to unarchive registry at path \"%@\". New Registry will be created to overwrite damaged one.", [self databaseFile]);
			NSLog(@"Caught %@: %@", [exception name], [exception  reason]);
			return self;
		}
		
		[myConnections addObjectsFromArray:hosts];
		NSEnumerator *e = [hosts objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur isKindOfClass:[CKHostCategory class]])
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostCategoryChanged
														   object:cur];
			}
			else
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostChanged
														   object:cur];
			}
		}
		//Enumerate the categories so we can make sure the hosts know of their category
		e = [[self allCategories] objectEnumerator];
		CKHostCategory *currentCategory;
		while ((currentCategory = [e nextObject]))
		{
			//Enumerate this categories hosts so we can set the category on it
			NSEnumerator *hostEnum = [[currentCategory hosts] objectEnumerator];
			CKHost *currentHost;
			while ((currentHost = [hostEnum nextObject]))
			{
				[currentHost setCategory:currentCategory];
			}
		}
	}
	return self;
}

- (void)dealloc
{
	[myDraggedItems release];
	[myBonjour release];
	[myLock release];
	[myConnections release];
	[myDatabaseFile release];
	
	[super dealloc];
}

- (oneway void)release
{
	
}

- (id)autorelease
{
	return self;
}

- (id)retain
{
	return self;
}

- (void)beginGroupEditing
{
	myIsGroupEditing = YES;
}

- (void)endGroupEditing
{
	myIsGroupEditing = NO;
	[self changed:nil];
}

- (NSString *)databaseFile
{
	return myDatabaseFile;
}

- (void)otherProcessChanged:(NSNotification *)notification
{
	if ([[NSProcessInfo processInfo] processIdentifier] != [[notification object] intValue])
	{
		[self willChangeValueForKey:@"connections"];
		unsigned idx = [myConnections indexOfObject:myBonjour];
		[myConnections removeAllObjects];
		NSArray *hosts = [NSKeyedUnarchiver unarchiveObjectWithFile:[self databaseFile]];
		[myConnections addObjectsFromArray:hosts];
		NSEnumerator *e = [hosts objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur isKindOfClass:[CKHostCategory class]])
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostCategoryChanged
														   object:cur];
			}
			else
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostChanged
														   object:cur];
			}
		}
		[myConnections insertObject:myBonjour atIndex:idx];
		[self didChangeValueForKey:@"connections"];
	}
}

- (void)changed:(NSNotification *)notification
{
	if (myIsGroupEditing) return;
	//write out the db to disk
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *lockPath = @"/tmp/connection.registry.lock";
	
	if ([fm fileExistsAtPath:lockPath])
	{
		[self performSelector:_cmd withObject:nil afterDelay:0.0];
		return;
	}
	
	[fm createFileAtPath:lockPath contents:[NSData data] attributes:nil];
	unsigned idx = [myConnections indexOfObject:myBonjour];
	[myConnections removeObject:myBonjour];
	[NSKeyedArchiver archiveRootObject:myConnections toFile:[self databaseFile]];
	[myConnections insertObject:myBonjour atIndex:idx];
	[fm removeFileAtPath:lockPath handler:nil];
	
	NSString *pid = [[NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]] retain];
	[myCenter postNotificationName:CKRegistryNotification object:pid userInfo:nil];
	[pid release];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKRegistryChangedNotification object:nil];
}

- (void)insertCategory:(CKHostCategory *)category atIndex:(unsigned)index
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostCategoryChanged
											   object:category];
	[self willChangeValueForKey:@"connections"];
	[myConnections insertObject:category atIndex:index];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)insertHost:(CKHost *)host atIndex:(unsigned)index
{
	if (index >= [myConnections count])
	{
		[self addHost:host];
		return;
	}
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostChanged
											   object:host];
	[self willChangeValueForKey:@"connections"];
	[myConnections insertObject:host atIndex:index];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)addCategory:(CKHostCategory *)category
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostCategoryChanged
											   object:category];
	[self willChangeValueForKey:@"connections"];
	[myConnections addObject:category];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)removeCategory:(CKHostCategory *)category
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:CKHostCategoryChanged
												  object:category];
	[self willChangeValueForKey:@"connections"];
	[myConnections removeObject:category];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)addHost:(CKHost *)connection
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostChanged
											   object:connection];
	[self willChangeValueForKey:@"connections"];
	[myConnections addObject:connection];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)removeHost:(CKHost *)connection
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:CKHostChanged
												  object:connection];
	[self willChangeValueForKey:@"connections"];
	[myConnections removeObject:connection];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (NSArray *)connections
{
	if (myFilter)
	{
		return [NSArray arrayWithArray:myFilteredHosts];
	}
	return [NSArray arrayWithArray:myConnections];
}

extern NSSize CKLimitMaxWidthHeight(NSSize ofSize, float toMaxDimension);

- (void)recursivelyCreate:(CKHostCategory *)cat withMenu:(NSMenu *)menu
{
	NSEnumerator *e = [[cat hosts] objectEnumerator];
	id cur;
	
	NSMenuItem *item;
	
	while ((cur = [e nextObject]))
	{
		if ([cur isKindOfClass:[CKHost class]])
		{
			item = [[NSMenuItem alloc] initWithTitle:[cur annotation] ? [cur annotation] : [cur name]
											  action:@selector(connectFromBookmarkMenuItem:)
									   keyEquivalent:@""];
			[item setRepresentedObject:cur];
			NSImage *icon = [[cur icon] copy];
			[icon setScalesWhenResized:YES];
			[icon setSize:CKLimitMaxWidthHeight([icon size],16)];
			[item setImage:icon];
			[icon release];
			[menu addItem:item];
			[item release];
		}
		else
		{
			item = [[NSMenuItem alloc] initWithTitle:[cur name]
											  action:nil
									   keyEquivalent:@""];
			NSMenu *subMenu = [[NSMenu alloc] initWithTitle:[cur name]];
			[item setSubmenu:subMenu];
			[item setRepresentedObject:cur];
			NSImage *icon = [[cur icon] copy];
			[icon setScalesWhenResized:YES];
			[icon setSize:CKLimitMaxWidthHeight([icon size],16)];
			[item setImage:icon];
			[icon release];
			[menu addItem:item];
			[item release];
			[subMenu release];
			[self recursivelyCreate:cur withMenu:subMenu];
		}
	}
}

- (NSMenu *)menu
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"connections"];
	
	NSEnumerator *e = [myConnections objectEnumerator];
	id cur;
	
	NSMenuItem *item;
	
	while ((cur = [e nextObject]))
	{
		NSImage *icon = [[cur icon] copy];
		[icon setScalesWhenResized:YES];
		[icon setSize:CKLimitMaxWidthHeight([icon size],16)];
		if ([cur isKindOfClass:[CKHost class]])
		{
			item = [[NSMenuItem alloc] initWithTitle:[cur annotation] ? [cur annotation] : [cur name]
											  action:@selector(connectFromBookmarkMenuItem:)
									   keyEquivalent:@""];
			[item setRepresentedObject:cur];
			[item setImage:icon];
			[menu addItem:item];
			[item release];
		}
		else
		{
			item = [[NSMenuItem alloc] initWithTitle:[cur name]
											  action:nil
									   keyEquivalent:@""];
			NSMenu *subMenu = [[[NSMenu alloc] initWithTitle:[cur name]] autorelease];
			[item setSubmenu:subMenu];			
			[item setRepresentedObject:cur];
			[item setImage:icon];
			[menu addItem:item];
			[item release];
			[self recursivelyCreate:cur withMenu:subMenu];
		}
		[icon release];
	}
	
	return [menu autorelease];
}

- (NSArray *)allHostsWithinItems:(NSArray *)itemsToSearch
{
	NSMutableArray *allHosts = [NSMutableArray array];
	NSEnumerator *itemsToSearchEnumerator = [itemsToSearch objectEnumerator];
	id currentItem;
	while (currentItem = [itemsToSearchEnumerator nextObject])
	{
		if ([[currentItem className] isEqualToString:@"CKHost"])
		{
			[allHosts addObject:(CKHost *)currentItem];
		}
		else if ([[currentItem className] isEqualToString:@"CKHostCategory"])
		{
			[allHosts addObjectsFromArray:[self allHostsWithinItems:[(CKHostCategory *)currentItem hosts]]];
		}
	}
	return allHosts;
}

- (NSArray *)allHosts
{
	return [self allHostsWithinItems:myConnections];
}

- (NSArray *)hostsMatching:(NSString *)query
{
	NSPredicate *filter = nil;
	@try {
		filter = [NSPredicate predicateWithFormat:query];
	} 
	@catch (NSException *ex) {
		
	}
	if (!filter)
	{
		filter = [NSPredicate predicateWithFormat:@"host contains[cd] %@ OR username contains[cd] %@ OR annotation contains[cd] %@ OR protocol contains[cd] %@ OR url.absoluteString contains[cd] %@", query, query, query, query, query];
	}
	return [[self allHosts] filteredArrayUsingPredicate:filter];
}

- (NSArray *)allCategoriesWithinItems:(NSArray *)itemsToSearch
{
	NSMutableArray *allCategories = [NSMutableArray array];
	NSEnumerator *itemsToSearchEnumerator = [itemsToSearch objectEnumerator];
	id currentItem;
	while (currentItem = [itemsToSearchEnumerator nextObject])
	{
		if ([[currentItem className] isEqualToString:@"CKHostCategory"])
		{
			[allCategories addObject:(CKHostCategory *)currentItem];
			[allCategories addObjectsFromArray:[self allCategoriesWithinItems:[(CKHostCategory *)currentItem childCategories]]];
		}
	}
	return allCategories;
}

- (NSArray *)allCategories
{
	return [self allCategoriesWithinItems:myConnections];
}

#pragma mark -
#pragma mark Outline View Data Source

- (void)setFilterString:(NSString *)filter
{
	if (filter != myFilter)
	{
		[myFilter autorelease];
		[myFilteredHosts autorelease];
		
		if ([filter isEqualToString:@""])
		{
			myFilter = nil;
			myFilteredHosts = nil;
		}
		else
		{
			myFilter = [filter copy];
			myFilteredHosts = [[self hostsMatching:filter] retain];
		}
		[myOutlineView reloadData];
	}
}

- (void)handleFilterableOutlineView:(NSOutlineView *)view
{
	myOutlineView = view;
	[myOutlineView setDataSource:self];
}

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (myFilter)
	{
		return [myFilteredHosts count];
	}
	if (item == nil)
	{
		return [[self connections] count];
	}
	else if ([item isKindOfClass:[CKHostCategory class]])
	{
		return [[item childCategories] count];
	}
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	if (myFilter)
	{
		return [myFilteredHosts objectAtIndex:index];
	}
	if (item == nil)
	{
		return [[self connections] objectAtIndex:index];
	}
	return [[item childCategories] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	if (myFilter) return NO;
	return [item isKindOfClass:[CKHostCategory class]] && [[item childCategories] count] > 0 ;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	//We have a large icon here, we need to scale it to the nearest base 2 size, based on the rowheight of the outlineview.
	float widthAndHeightDimension = pow(2, floor(log2([outlineView rowHeight]))); // Gets us 16, 32, 64, 128, etc.
	NSSize nearestSize = NSMakeSize(widthAndHeightDimension, widthAndHeightDimension);
	NSImage *icon = [item iconWithSize:nearestSize];
	
	if ([item isKindOfClass:[CKHostCategory class]])
	{		
		return [NSDictionary dictionaryWithObjectsAndKeys:[item name], CKHostCellStringValueKey, icon, CKHostCellImageValueKey, nil];
	}
	else
	{
		NSString *primary = [item annotation];
		NSString *secondary = nil;
		BOOL useHostName = [[[NSUserDefaults standardUserDefaults] objectForKey:@"CKHostCellUsesHostName"] boolValue];
		if (!primary || [primary isEqualToString:@""])
		{
			if (useHostName)
			{
				primary = [item host];
			}
			else
			{
				primary = [item name];
			}
		}
		else
		{
			if (useHostName)
			{
				secondary = [item host];
			}
			else
			{
				secondary = [item name];
			}
		}
		
		if ([primary isEqualToString:secondary])
		{
			secondary = nil;
		}
		
		// annotation is last incase it is nil and finishes the dictionary there.
		return [NSDictionary dictionaryWithObjectsAndKeys:primary, CKHostCellStringValueKey, icon, CKHostCellImageValueKey, secondary, CKHostCellSecondaryStringValueKey, nil];
	}
	return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([item isKindOfClass:[CKHostCategory class]] && [item isEditable])
	{
		[((CKHostCategory *)item) setName:object];
	}
	else if ([item isKindOfClass:[CKHost class]])
	{
		[((CKHost *)item) setAnnotation:object];
	}
}

- (void)recursivelyWrite:(CKHostCategory *)category to:(NSString *)path
{
	NSEnumerator *e = [[category hosts] objectEnumerator];
	id cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur isKindOfClass:[CKHost class]])
		{
			[cur createDropletAtPath:path];
		}
		else
		{
			NSString *catDir = [path stringByAppendingPathComponent:[cur name]];
			[[NSFileManager defaultManager] createDirectoryAtPath:catDir attributes:nil];
			[self recursivelyWrite:cur to:catDir];
		}
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	// we write out all the hosts /tmp
	NSString *wd = [NSString stringWithFormat:@"/tmp/ck"];
	[[NSFileManager defaultManager] createDirectoryAtPath:wd attributes:nil];
	[outlineView setDraggingSourceOperationMask:NSDragOperationCopy  
									   forLocal:NO];
	[pboard declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil] owner:nil];
	NSMutableArray *files = [NSMutableArray array];
	NSEnumerator *e = [items objectEnumerator];
	id cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur isKindOfClass:[CKHost class]])
		{
			@try {
				[files addObject:[cur createDropletAtPath:wd]];
			}
			@catch (NSException *ex) {
				
			}
		}
		else
		{
			NSString *catDir = [wd stringByAppendingPathComponent:[cur name]];
			[[NSFileManager defaultManager] createDirectoryAtPath:catDir attributes:nil];
			[files addObject:catDir];
			[self recursivelyWrite:cur to:catDir];
		}
	}
	[pboard setPropertyList:files forType:NSFilenamesPboardType];
	[myDraggedItems removeAllObjects];
	[myDraggedItems addObjectsFromArray:items];
	
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id)dropInfo proposedItem:(id)item proposedChildIndex:(int)proposedChildIndex
{
	if ([myDraggedItems count] > 0)
	{
		//Check if dragged item is part of an uneditable category
		id draggedItem = [myDraggedItems objectAtIndex:0];
		BOOL isNotEditable = ([draggedItem category] && ![[draggedItem category] isEditable]);
		if (isNotEditable)
		{
			return NSDragOperationNone;
		}
	}
	NSString *itemPath = [[[dropInfo draggingPasteboard] propertyListForType:NSFilenamesPboardType] objectAtIndex:0];
	if ([itemPath isEqualToString:@"/tmp/ck/Bonjour"] || [[item className] isEqualToString:@"CKBonjourCategory"] ||[[[item category] className] isEqualToString:@"CKBonjourCategory"])
	{
		return NSDragOperationNone;
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:[itemPath stringByAppendingPathComponent:@"Contents/Resources/configuration.ckhost"]] && ! [itemPath hasPrefix:@"/tmp/ck"])
	{
		//Drag From Finder
		if ([item isKindOfClass:[CKHostCategory class]])
		{
			[outlineView setDropItem:item dropChildIndex:proposedChildIndex];
		}
		else
		{
			[outlineView setDropItem:nil dropChildIndex:proposedChildIndex];
		}
		return NSDragOperationCopy;
	}
	else if (item == nil || [item isKindOfClass:[CKHostCategory class]])
	{
		//Drag to re-order
		[outlineView setDropItem:item dropChildIndex:proposedChildIndex];
		return NSDragOperationMove;
	}
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView acceptDrop:(id )info item:(id)item childIndex:(int)index
{
	NSArray *dropletPaths = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSEnumerator *dropletPathEnumerator = [dropletPaths objectEnumerator];
	NSString *currentDropletPath;
	while (currentDropletPath = [dropletPathEnumerator nextObject])
	{
		if (![currentDropletPath hasPrefix:@"/tmp/ck"])
		{
			//Drag to import
			NSString *configurationFilePath = [currentDropletPath stringByAppendingPathComponent:@"Contents/Resources/configuration.ckhost"];
			CKHost *dropletHost = [NSKeyedUnarchiver unarchiveObjectWithFile:configurationFilePath];
			if (dropletHost)
			{
				//Dragged a Bookmark
				if ([[item className] isEqualToString:@"CKHostCategory"])
				{
					//Into a Category
					if (index == -1)
					{
						[item addHost:dropletHost];
					}
					else
					{
						[item insertHost:dropletHost atIndex:index];
					}
				}
				else
				{
					//Into root
					if (index == -1)
					{
						[self addHost:dropletHost];					
					}
					else
					{
						[self insertHost:dropletHost atIndex:index];
					}
				}
			}
		}
		else
		{
			NSEnumerator *itemsToMoveEnumerator = [myDraggedItems objectEnumerator];
			id currentItem = nil;
			[self beginGroupEditing];
			while ((currentItem = [itemsToMoveEnumerator nextObject]))
			{
				//Make sure the item we dragged isn't attempting to be dragged into itself!
				if (currentItem == item)
				{
					continue;
				}
				if ([[currentItem className] isEqualToString:@"CKHost"])
				{
					BOOL hasRemoved = NO;
					NSEnumerator *allCategoriesEnumerator = [[self allCategories] objectEnumerator];
					CKHostCategory *currentCategory;
					BOOL cameFromCategory = YES;
					while (currentCategory = [allCategoriesEnumerator nextObject])
					{
						if ([[currentCategory hosts] containsObject:currentItem])
						{
							[currentCategory removeHost:currentItem];
							hasRemoved = YES;
							break;
						}
					}
					if (!hasRemoved)
					{
						cameFromCategory = NO;
						[self removeHost:currentItem];
					}
					if (!item)
					{
						//Add new Host to the root.
						if (index == -1)
						{
							[self addHost:currentItem];
						}
						else
						{
							[self insertHost:currentItem atIndex: cameFromCategory ? index : index-1];
						}
					}
					else
					{
						//Add the Host to it's new parent category.
						if (index == -1)
						{
							[item addHost:currentItem];
						}
						else
						{
							[item insertHost:currentItem atIndex:index];
						}
					}
				}
				else
				{
					BOOL hasRemoved = NO;
					NSEnumerator *allCategoriesEnumerator = [[self allCategories] objectEnumerator];
					CKHostCategory *currentCategory;
					BOOL cameFromCategory = YES;
					while (currentCategory = [allCategoriesEnumerator nextObject])
					{
						if ([[currentCategory childCategories] containsObject:currentItem])
						{
							[currentCategory removeChildCategory:currentItem];
							hasRemoved = YES;
						}
					}
					if (!hasRemoved)
					{
						cameFromCategory = NO;
						[self removeCategory:currentItem];
					}
					if (!item)
					{
						//Add new category to the root.
						if (index == -1)
						{
							[self addCategory:currentItem];
						}
						else
						{
							[self insertCategory:currentItem atIndex: cameFromCategory ? index : index-1];
						}
					}
					else
					{		
						//Add new category to its new parent category.
						if (index == -1)
						{
							[item addChildCategory:currentItem];
						}
						else
						{
							[item insertChildCategory:currentItem atIndex:index];
						}
					}
				}
				[myDraggedItems removeAllObjects];
			}
			[self endGroupEditing];						
		}
	}
	return YES;
}

@end

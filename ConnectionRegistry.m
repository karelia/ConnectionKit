//
//  ConnectionRegistry.m
//  Connection
//
//  Created by Greg Hulands on 15/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "ConnectionRegistry.h"
#import "CKHostCategory.h"
#import "CKBonjourCategory.h"
#import "CKHost.h"
#import "AbstractConnection.h"
#import "CKHostCell.h"

static NSLock *sRegistryLock = nil;
static BOOL sRegistryCanInit = NO;
static ConnectionRegistry *sRegistry = nil;

NSString *CKLocalRegistryPboardType = @"CKLocalRegistryPboardType";
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
		myBonjour = [[CKBonjourCategory alloc] init];
		[myConnections addObject:myBonjour];
		
		[myCenter addObserver:self
					 selector:@selector(otherProcessChanged:)
						 name:CKRegistryNotification
					   object:nil];
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
		
	}
	return self;
}

- (void)dealloc
{
	[myDraggedItems release];
	[myBonjour release];
	[myLock release];
	[myConnections release];
	
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
	return [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Preferences"] stringByAppendingPathComponent:@"com.connectionkit.registry"];
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
	
	NSString *pid = [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]];
	[myCenter postNotificationName:CKRegistryNotification object:pid userInfo:nil];
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

- (id)actualItemWithAnnotation:(NSString *)optionalAnnotation name:(NSString *)optionalName host:(NSString *)optionalHost username:(NSString *)optionalUsername fromItems:(NSArray *)items 
{
	NSEnumerator *hostsEnumerator = [items objectEnumerator];
	id currentHost = nil;
	int matchesNeeded = 0;
	int currentMatches = 0;
	if (optionalAnnotation)
	{
		matchesNeeded++;
	}
	if (optionalHost)
	{
		matchesNeeded++;
	}
	if (optionalUsername)
	{
		matchesNeeded++;
	}
	if (optionalName)
	{
		matchesNeeded++;
	}
	while (currentHost = [hostsEnumerator nextObject])
	{
		currentMatches = 0;
		if ([[currentHost className] isEqualToString:@"CKHost"])
		{
			if ([currentHost annotation])
			{
				if ([[currentHost annotation] isEqual:optionalAnnotation])
				{
					currentMatches++;
				}
			}
			if ([currentHost host])
			{
				if ([[currentHost host] isEqual:optionalHost])
				{
					currentMatches++;
				}
			}
			if ([currentHost username])
			{
				if ([[currentHost username] isEqual:optionalUsername])
				{
					currentMatches++;
				}
			}
			if (matchesNeeded == currentMatches)
			{
				return (CKHost *)currentHost;
			}
		}
		else
		{
			if ([currentHost name])
			{
				if ([[currentHost name] isEqual:optionalName])
				{
					currentMatches++;
				}
			}
			if (matchesNeeded == currentMatches)
			{
				return (CKHostCategory *)currentHost;
			}
		}
	}
	return nil;
}

#pragma mark -
#pragma mark Outline View Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
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
	if (item == nil)
	{
		return [[self connections] objectAtIndex:index];
	}
	return [[item childCategories] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isKindOfClass:[CKHostCategory class]] && [[item childCategories] count] > 0 ;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([item isKindOfClass:[CKHostCategory class]])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:[item name], CKHostCellStringValueKey, [item icon], CKHostCellImageValueKey, nil];
	}
	else
	{
		NSString *val = nil;
		if ([item annotation] && [[item annotation] length] > 0)
		{
			val = [item annotation];
		}
		else
		{
			val = [item name];
		}
		return [NSDictionary dictionaryWithObjectsAndKeys:val, CKHostCellStringValueKey, [item icon], CKHostCellImageValueKey, nil];
	}
	return nil;
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
	[pboard declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, CKLocalRegistryPboardType, nil] owner:nil];
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
	[myDraggedItems addObjectsFromArray:items];
	
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView*)outlineView validateDrop:(id)info proposedItem:(id)item proposedChildIndex:(int)index
{
	NSArray *draggedItems = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSEnumerator *draggedItemsEnumerator = [draggedItems objectEnumerator];
	NSString *currentItemPath;
	BOOL canAcceptDrag = NO;
	while ((currentItemPath = [draggedItemsEnumerator nextObject]) && !canAcceptDrag)
	{
		if (item == nil && index == -1)
		{
			canAcceptDrag = YES;
			[outlineView setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
		}
		else if ([[item className] isEqualToString:@"CKHostCategory"])
		{
			canAcceptDrag = YES;
			[outlineView setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex+1];
			break;
		}
		if ([[NSFileManager defaultManager] fileExistsAtPath:[currentItemPath stringByAppendingPathComponent:@"Contents/Resources/configuration.ckhost"]] && ![currentItemPath hasPrefix:@"/tmp/ck"])
		{  
			//Drag from Finder
			canAcceptDrag = YES;
			[outlineView setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
			break;
		}
	}
	if (canAcceptDrag)
	{
		return NSDragOperationCopy;
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
					[item addHost:dropletHost];
				}
				else
				{
					//Into root
					[self addHost:dropletHost];					
				}
			}
		}
		else
		{
			NSEnumerator *itemsToMoveEnumerator = [myDraggedItems objectEnumerator];
			id currentItem = nil;
			while (currentItem = [itemsToMoveEnumerator nextObject])
			{
				//Make sure the item we dragged isn't attempting to be dragged into itself!
				if (currentItem != item)
				{
					if ([[currentItem className] isEqualToString:@"CKHost"])
					{
						//Moving a Host
						if ([currentItem category])
						{
							//Remove the host from the parent category
							[[currentItem category] removeHost:currentItem];
						}
						else
						{
							//Remove the host from the root.
							[self removeHost:currentItem];
						}
						if (item == nil)
						{
							//Add new Host to the root.
							[self addHost:currentItem];
						}
						else
						{
							//Add the Host to it's new parent category.
							[item addHost:currentItem];
						}
					}
					else
					{
						//Moving a category
						if ([currentItem category])
						{
							//Remove the category from the parent category
							[[currentItem category] removeChildCategory:currentItem];
						}
						else
						{
							//Remove the category from the root
							[self removeCategory:currentItem];
						}
						if (item == nil)
						{
							//Add new category to the root.
							[self addCategory:currentItem];
						}
						else
						{		
							//Add new category to its new parent category.
							[item addChildCategory:currentItem];
						}
					}
				}
				[myDraggedItems removeAllObjects];
			}
		}
	}
	return YES;
}

@end

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

static ConnectionRegistry *sharedRegistry = nil;
static BOOL sharedRegistryIsInitializing = NO;
static NSString *sRegistryDatabase = nil;

NSString *CKRegistryNotification = @"CKRegistryNotification";
NSString *CKRegistryChangedNotification = @"CKRegistryChangedNotification";
NSString *CKDraggedBookmarksPboardType = @"CKDraggedBookmarksPboardType";

@interface ConnectionRegistry (Private)
- (void)otherProcessChanged:(NSNotification *)notification;
- (NSString *)databaseFile;
- (void)changed:(NSNotification *)notification;
- (NSArray *)hostsFromDatabaseFile;

- (BOOL)itemIsLeopardSourceGroupHeader:(id)item;

@end

@implementation ConnectionRegistry

#pragma mark -
#pragma mark Getting Started / Tearing Down
+ (id)sharedRegistry
{
	if (sharedRegistryIsInitializing)
		return nil;
	
	if (!sharedRegistry)
	{
		sharedRegistryIsInitializing = YES;
		[[ConnectionRegistry alloc] init];
		sharedRegistryIsInitializing = NO;
	}
	return sharedRegistry;
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
	if ((self = [super init]))
	{
		myLock = [[NSLock alloc] init];
		myCenter = [NSDistributedNotificationCenter defaultCenter];
		myLeopardSourceListGroups = [[NSMutableArray alloc] init];
		myConnections = [[NSMutableArray alloc] init];
		myDraggedItems = [[NSMutableArray alloc] init];
		myDatabaseFile = [[ConnectionRegistry registryDatabase] copy];
		myBonjour = [[CKBonjourCategory alloc] init];
		myOutlineViews = [[NSMutableArray array] retain];
		[myConnections addObject:myBonjour];
		
		[myCenter addObserver:self
					 selector:@selector(otherProcessChanged:)
						 name:CKRegistryNotification
		
					   object:nil];
		
		NSArray *hosts = [self hostsFromDatabaseFile];		
		[myConnections addObjectsFromArray:hosts];
				
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(changed:)
													 name:CKHostCategoryChanged
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(changed:)
													 name:CKHostChanged
												   object:nil];		

		//Enumerate the categories so we can make sure the hosts know of their category
		NSEnumerator *e = [[self allCategories] objectEnumerator];
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
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[myLeopardSourceListGroups release];
	[myDraggedItems release];
	[myBonjour release];
	[myLock release];
	[myConnections release];
	[myDatabaseFile release];
	[myOutlineViews release];
	
	[super dealloc];
}

+ (id)allocWithZone:(NSZone *)zone
{
	if (!sharedRegistry)
	{
		sharedRegistry = [super allocWithZone:zone];
		return sharedRegistry;
	}
	return nil;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (unsigned)retainCount
{
    return UINT_MAX;  //denotes an object that cannot be released
}

- (void)release
{
    //do nothing
}

- (id)autorelease
{
    return self;
}

#pragma mark -
#pragma mark Item Management
- (NSArray *)connections
{
	if (myFilter)
	{
		return [NSArray arrayWithArray:myFilteredHosts];
	}
	return [NSArray arrayWithArray:myConnections];
}

- (void)insertItem:(id)item atIndex:(unsigned)index
{
	[self willChangeValueForKey:@"connections"];
	[myConnections insertObject:item atIndex:index];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)addItem:(id)item
{
	[self willChangeValueForKey:@"connections"];
	[myConnections addObject:item];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)removeItem:(id)item
{
	[self willChangeValueForKey:@"connections"];
	int index = [myConnections indexOfObjectIdenticalTo:item];
	[myConnections removeObjectAtIndex:index];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

#pragma mark CKHosts
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

- (void)insertHost:(CKHost *)host atIndex:(unsigned)index
{
	[self insertItem:host atIndex:index];
}

- (void)addHost:(CKHost *)connection
{
	[self addItem:connection];
}

- (void)removeHost:(CKHost *)connection
{
	[self removeItem:connection];
}

#pragma mark CKHostCategory
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

- (void)insertCategory:(CKHostCategory *)category atIndex:(unsigned)index
{
	[self insertItem:category atIndex:index];
}

- (void)addCategory:(CKHostCategory *)category
{
	[self addItem:category];
}

- (void)removeCategory:(CKHostCategory *)category
{
	[self removeItem:category];
}

#pragma mark Database Management
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

- (NSArray *)hostsFromDatabaseFile
{
	NSArray *hosts = nil;
	if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"CKRegistryDatabaseUsesPlistFormat"] boolValue])
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:[self databaseFile]])
		{
			hosts = [NSArray arrayWithContentsOfFile:[self databaseFile]];
			
			// convert to classes
			NSMutableArray *cats = [NSMutableArray array];
			NSEnumerator *e = [hosts objectEnumerator];
			id cur;
			
			while ((cur = [e nextObject]))
			{
				if ([[cur objectForKey:@"class"] isEqualToString:@"category"])
				{
					CKHostCategory *cat = [[CKHostCategory alloc] initWithDictionary:cur];
					[cats addObject:cat];
					[cat release];
				}
				else
				{
					CKHost *host = [[CKHost alloc] initWithDictionary:cur];
					[cats addObject:host];
					[host release];
				}
			}
			hosts = [NSArray arrayWithArray:cats];
		}
	}
	else
	{
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
			NSLog(@"Caught %@: %@", [exception name], [exception reason]);
		}
	}
	return hosts;
}

- (void)otherProcessChanged:(NSNotification *)notification
{
	if ([[NSProcessInfo processInfo] processIdentifier] != [[notification object] intValue])
	{
		[self willChangeValueForKey:@"connections"];
		unsigned idx = [myConnections indexOfObject:myBonjour];
		[myConnections removeAllObjects];
		NSArray *hosts = [self hostsFromDatabaseFile];
		[myConnections addObjectsFromArray:hosts];

		if (myUsesLeopardStyleSourceList)
		{
			[self setUsesLeopardStyleSourceList:YES]; //Redoes all the jazz
		}
		else
		{
			[myConnections insertObject:myBonjour atIndex:idx];
		}
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
		databaseWriteFailCount++;
		if (databaseWriteFailCount > 4)
		{
			//The database has been locked for over 2 seconds. CK is obviously not writing to it, but the lock still exists. Remove the lock
			NSLog(@"CKRegistry has been locked for over 2 seconds. Removing Lock.");
			[fm removeFileAtPath:lockPath handler:nil];
			databaseWriteFailCount = 0;
		}
		else
		{
			[self performSelector:_cmd withObject:nil afterDelay:0.5];
			return;
		}
	}
	
	[fm createFileAtPath:lockPath contents:[NSData data] attributes:nil];
	unsigned idx = 0; // clang complains that idx is uninitialized, so let's init to 0
	if (!myUsesLeopardStyleSourceList)
	{
		idx = [myConnections indexOfObject:myBonjour];
		[myConnections removeObject:myBonjour];
	}
	// write to the database
	if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"CKRegistryDatabaseUsesPlistFormat"] boolValue])
	{
		NSMutableArray *plist = [NSMutableArray array];
		NSEnumerator *e = [myConnections objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			[plist addObject:[cur plistRepresentation]];
		}
		NSString *err = nil;
		[[NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0 errorDescription:&err] writeToFile:[self databaseFile] atomically:YES];
		if (err)
		{
			NSLog(@"%@", err);
		}
	}
	else
	{
		[NSKeyedArchiver archiveRootObject:myConnections toFile:[self databaseFile]];
	}
	if (myUsesLeopardStyleSourceList)
	{
		[self setUsesLeopardStyleSourceList:YES];
	}
	else
	{
		[myConnections insertObject:myBonjour atIndex:idx];
	}
	[fm removeFileAtPath:lockPath handler:nil];
	
	NSString *pid = [[NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]] retain];
	[myCenter postNotificationName:CKRegistryNotification object:pid userInfo:nil];
	[pid release];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKRegistryChangedNotification object:nil];
    [myOutlineViews makeObjectsPerformSelector:@selector(reloadData)];
}
#pragma mark Menu

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
			[item setTarget:[[self outlineView] delegate]];
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
			[item setTarget:[[self outlineView] delegate]];
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

#pragma mark Leopard Style Source List
- (void)setUsesLeopardStyleSourceList:(BOOL)flag
{
	if (myUsesLeopardStyleSourceList == flag)
		return;
	/*
		See http://brianamerige.com/blog/2008/01/31/connectionkit-leopard-styled-source-list-notes/ for more information on how to fully implement the Leopard Style source list.
	*/
	myUsesLeopardStyleSourceList = flag;
	if (!flag)
		return;
	[myConnections removeObject:myBonjour];
	[myLeopardSourceListGroups removeAllObjects];
	
	NSDictionary *bonjourGroupItem = [NSDictionary dictionaryWithObjectsAndKeys:[myBonjour childCategories], @"Children", 
									  [NSNumber numberWithBool:YES], @"IsSourceGroup", 
									  @"BONJOUR", @"Name", nil];
	[myLeopardSourceListGroups insertObject:bonjourGroupItem atIndex:0];
	
	NSDictionary *bookmarksGroupItem = [NSDictionary dictionaryWithObjectsAndKeys:myConnections, @"Children", 
									  [NSNumber numberWithBool:YES], @"IsSourceGroup", 
									  @"BOOKMARKS", @"Name", nil];
	[myLeopardSourceListGroups addObject:bookmarksGroupItem];
}
- (BOOL)itemIsLeopardSourceGroupHeader:(id)item
{
	return ([myLeopardSourceListGroups containsObject:item]);
}

#pragma mark Droplet
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
#pragma mark -
#pragma mark NSOutlineView Management
- (NSOutlineView *)outlineView
{
	return [myOutlineViews objectAtIndex:0];
}

#pragma mark Filtering
- (void)setFilterString:(NSString *)filter
{
	if (filter == myFilter)
	{
		return;
	}
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
	[myOutlineViews makeObjectsPerformSelector:@selector(reloadData)];
}

- (void)handleFilterableOutlineView:(NSOutlineView *)view
{
	[myOutlineViews addObject:view];
	[view setDataSource:self];
	[view registerForDraggedTypes:[NSArray arrayWithObjects:CKDraggedBookmarksPboardType, NSFilenamesPboardType, nil]];
}

#pragma mark NSOutlineView DataSource
- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (myFilter)
	{
		return [myFilteredHosts count];
	}
	if (myUsesLeopardStyleSourceList)
	{
		if (!item)
		{
			return [myLeopardSourceListGroups count];
		}
		else if ([self itemIsLeopardSourceGroupHeader:item])
		{
			return [[item objectForKey:@"Children"] count];
		}
		else if ([item isKindOfClass:[CKHostCategory class]])
		{
			return [[item childCategories] count];
		}
	}
	else
	{
		if (item == nil)
		{
			return [[self connections] count];
		}
		else if ([item isKindOfClass:[CKHostCategory class]])
		{
			return [[item childCategories] count];
		}
	}
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	if (myFilter)
		return [myFilteredHosts objectAtIndex:index];
	if (myUsesLeopardStyleSourceList)
	{
		if (!item)
			return [myLeopardSourceListGroups objectAtIndex:index];
		else if ([self itemIsLeopardSourceGroupHeader:item])
			return [[item objectForKey:@"Children"] objectAtIndex:index];
		return [[item childCategories] objectAtIndex:index];
	}
	else
	{
		if (item == nil)
			return [[self connections] objectAtIndex:index];
		return [[item childCategories] objectAtIndex:index];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	if (myFilter) return NO;
	if (myUsesLeopardStyleSourceList)
	{
		if ([self itemIsLeopardSourceGroupHeader:item])
		{
			return YES;
		}
	}
	return [item isKindOfClass:[CKHostCategory class]] && [[item childCategories] count] > 0 ;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{	
	if ([self itemIsLeopardSourceGroupHeader:item])
		return [item objectForKey:@"Name"];
	
    NSString *ident = [tableColumn identifier];
    
    if ([ident isEqualToString:@"connType"])
    {
        if ([item isKindOfClass:[CKHost class]])
        {
            return [item connectionType];
        }
    }
    else if ([item isKindOfClass:[CKHost class]] || [item isKindOfClass:[CKHostCategory class]])
    {
        //We have a large icon here, we need to scale it to the nearest base 2 size, based on the rowheight of the outlineview.
        float widthAndHeightDimension = pow(2, floor(log2([outlineView rowHeight]))); // Gets us 16, 32, 64, 128, etc.
        NSSize nearestSize = NSMakeSize(widthAndHeightDimension, widthAndHeightDimension);
        NSImage *icon = [item iconWithSize:nearestSize];
        
        if ([item isKindOfClass:[CKHostCategory class]])
            return [NSDictionary dictionaryWithObjectsAndKeys:[item name], CKHostCellStringValueKey, icon, CKHostCellImageValueKey, nil];
        else
        {
            NSString *primary = [item annotation];
            NSString *secondary = nil;
            BOOL useHostName = [[[NSUserDefaults standardUserDefaults] objectForKey:@"CKHostCellUsesHostName"] boolValue];
            if (!primary || [primary isEqualToString:@""])
				primary = (useHostName) ? [item host] : [item name];
            else
				secondary = (useHostName) ? [item host] : [item name];
            
            if ([primary isEqualToString:secondary])
                secondary = nil;
            
            // annotation is last incase it is nil and finishes the dictionary there.
            return [NSDictionary dictionaryWithObjectsAndKeys:primary, CKHostCellStringValueKey, icon, CKHostCellImageValueKey, secondary, CKHostCellSecondaryStringValueKey, nil];
        }
    }
	
	return nil;
}

#pragma mark NSOutlineView Delegate

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([item isKindOfClass:[CKHostCategory class]] && [item isEditable])
	{
		[((CKHostCategory *)item) setName:object];
	}
	else if ([item isKindOfClass:[CKHost class]] && [item isEditable])
	{
		[(CKHost *)item setAnnotation:object];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	BOOL skipDroplets = NO;
	NSNumber *skipDropletPref = [[NSUserDefaults standardUserDefaults] objectForKey:@"CKSkipHostDropletCreation"];
	if (skipDropletPref)
	{
		skipDroplets = [skipDropletPref boolValue];
	}
	
	// we write out all the hosts /tmp
	NSString *wd = [NSString stringWithFormat:@"/tmp/ck"];
	[[NSFileManager defaultManager] createDirectoryAtPath:wd attributes:nil];
	[outlineView setDraggingSourceOperationMask:NSDragOperationCopy  
									   forLocal:NO];
	NSMutableArray *types = [NSMutableArray arrayWithObject:CKDraggedBookmarksPboardType];
	if (!skipDroplets)
	{
		[types addObject:NSFilenamesPboardType];
	}
	[pboard declareTypes:types owner:nil];
	
	NSMutableArray *files = [NSMutableArray array];
	if (!skipDroplets)
	{
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
			else if (![cur isKindOfClass:[NSDictionary class]])
			{
				NSString *catDir = [wd stringByAppendingPathComponent:[cur name]];
				[[NSFileManager defaultManager] createDirectoryAtPath:catDir attributes:nil];
				[files addObject:catDir];
				[self recursivelyWrite:cur to:catDir];
			}
		}
		[pboard setPropertyList:files forType:NSFilenamesPboardType];
	}
	
	[pboard setPropertyList:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"InitiatedByDrag"] forType:CKDraggedBookmarksPboardType];
	[myDraggedItems removeAllObjects];
	[myDraggedItems addObjectsFromArray:items];
	return [files count] > 0; //Only allow the drag if we are actually dragging something we can drag (i.e., not a BONJOUR/BOOKMARK header)
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id)dropInfo proposedItem:(id)item proposedChildIndex:(int)proposedChildIndex
{
	NSPasteboard *pboard = [dropInfo draggingPasteboard];
	
	if ([[pboard types] indexOfObject:CKDraggedBookmarksPboardType] != NSNotFound)
	{
		//Check if dragged item is part of an uneditable category
		id draggedItem = [myDraggedItems objectAtIndex:0];
		BOOL isNotEditable = ([draggedItem category] && ![[draggedItem category] isEditable]) || ([item isKindOfClass:[CKHostCategory class]] && ![item isEditable]);		
		if (isNotEditable)
			return NSDragOperationNone;
		// don't allow a recursive drop
		if ([draggedItem isKindOfClass:[CKHostCategory class]])
		{
			if ([item isKindOfClass:[CKHostCategory class]] && [item isChildOf:draggedItem])
				return NSDragOperationNone;
		}
		if (myUsesLeopardStyleSourceList && [item isKindOfClass:[NSDictionary class]] && [[item objectForKey:@"Name"] isEqualToString:@"BONJOUR"])
			return NSDragOperationNone;
		// don't allow a host to get dropped on another host
		if ([item isKindOfClass:[CKHost class]])
			return NSDragOperationNone;
		return NSDragOperationMove;
	}
	else if ([[pboard types] indexOfObject:NSFilenamesPboardType] != NSNotFound)
	{
		NSString *itemPath = [[pboard propertyListForType:NSFilenamesPboardType] objectAtIndex:0];
		if ([itemPath isEqualToString:@"/tmp/ck/Bonjour"] || [item isKindOfClass:[NSDictionary class]] || [item isKindOfClass:[CKBonjourCategory class]] || [[item category] isKindOfClass:[CKBonjourCategory class]])
			return NSDragOperationNone;
		if ([[NSFileManager defaultManager] fileExistsAtPath:[itemPath stringByAppendingPathComponent:@"Contents/Resources/configuration.ckhost"]] && ! [itemPath hasPrefix:@"/tmp/ck"])
		{
			//Drag From Finder
			if ([item isKindOfClass:[CKHostCategory class]])
				[outlineView setDropItem:item dropChildIndex:proposedChildIndex];
			else
				[outlineView setDropItem:nil dropChildIndex:proposedChildIndex];
			return NSDragOperationCopy;
		}
		else if (item == nil || [item isKindOfClass:[CKHostCategory class]])
		{
			//Drag to re-order
			[outlineView setDropItem:item dropChildIndex:proposedChildIndex];
			return NSDragOperationMove;
		}
	}
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView acceptDrop:(id )info item:(id)item childIndex:(int)index
{
	NSPasteboard *pboard = [info draggingPasteboard];
	NSEnumerator *itemEnumerator = nil;
	id selectedItem = [outlineView itemAtRow:[outlineView selectedRow]];
	
	if ([[pboard types] indexOfObject:CKDraggedBookmarksPboardType] == NSNotFound)
	{
		// this is a drag of a droplet back in
		NSMutableArray *unarchivedHosts = [NSMutableArray array];
		NSArray *dropletPaths = [pboard propertyListForType:NSFilenamesPboardType];
		NSEnumerator *e = [dropletPaths objectEnumerator];
		NSString *cur;
		
		while ((cur = [e nextObject]))
		{
			NSString *configurationFilePath = [cur stringByAppendingPathComponent:@"Contents/Resources/configuration.ckhost"];
			CKHost *dropletHost = [NSKeyedUnarchiver unarchiveObjectWithFile:configurationFilePath];
			
			if (!dropletHost) continue;
			[unarchivedHosts addObject:dropletHost];
		}
		itemEnumerator = [unarchivedHosts objectEnumerator];
	}
	else
		itemEnumerator = [myDraggedItems objectEnumerator];
	
	id currentItem = nil;
	[self beginGroupEditing];
	while ((currentItem = [itemEnumerator nextObject]))
	{
		CKHostCategory *currentCategory = [currentItem category];
		unsigned currentIndex = NSNotFound;
		
		NSArray *parentConnections = (currentCategory) ? [currentCategory hosts] : myConnections;
		currentIndex = [parentConnections indexOfObjectIdenticalTo:currentItem];
		if (currentIndex != NSNotFound)
		{
			id parentOfCurrentItem = (currentCategory) ? (id)currentCategory : (id)self;
			[parentOfCurrentItem removeHost:currentItem];
		}
		
		// if we are moving around in the same category, then the index can get offset from the removal
		if (currentCategory == item)
			if (currentIndex < index) index--;
		
		//Add it in its new location
		id dropTarget = (!item || [item isKindOfClass:[NSDictionary class]]) ? self : item;
		if (index < 0 || index == NSNotFound)
			[dropTarget addHost:currentItem];
		else
			[dropTarget insertHost:currentItem atIndex:index];
	}
	[self endGroupEditing];
	[myDraggedItems removeAllObjects];
	
	//Maintain the selected item. We need to reloadData on the outlineView so the changes in data we just made are are seen by the rowForItem: call.
	[outlineView reloadData];
	[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[outlineView rowForItem:selectedItem]] byExtendingSelection:NO];	
	return YES;
}
@end

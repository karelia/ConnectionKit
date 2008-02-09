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

#import <Cocoa/Cocoa.h>

/*
 
		This class is used across applications to have a standard registry of known connections for 
		a user. This allows them to add/modify/delete connections they have and have them reflect in
		all applications that use the connection framework.
 
		The registry also is an NSOutlineView compliant data source so you can set the registry to handle
		the population of the view.
  
 */

@class CKHostCategory, CKBonjourCategory, CKHost;

@interface ConnectionRegistry : NSObject 
{
	NSMutableArray *myLeopardSourceListGroups;
	NSMutableArray *myConnections;
	NSMutableArray *myDraggedItems;
	NSString *myDatabaseFile;
	CKBonjourCategory *myBonjour;
	NSDistributedNotificationCenter *myCenter;
	NSLock *myLock;
	
	NSOutlineView *myOutlineView;
	NSString *myFilter;
	NSArray *myFilteredHosts;
	
	BOOL myIsGroupEditing;
	BOOL myUsesLeopardStyleSourceList;
	
	int databaseWriteFailCount;
}

// you can set a custom database if you don't want to use the default shared registry.
// I don't recommend it, but there are situations where this is needed.
+ (void)setRegistryDatabase:(NSString *)file;
+ (NSString *)registryDatabase;

+ (id)sharedRegistry; //use this. DO NOT alloc one yourself

- (void)beginGroupEditing;
- (void)endGroupEditing;

- (void)addCategory:(CKHostCategory *)category;
- (void)removeCategory:(CKHostCategory *)category;

- (void)insertCategory:(CKHostCategory *)category atIndex:(unsigned)index;
- (void)insertHost:(CKHost *)host atIndex:(unsigned)index;

- (void)addHost:(CKHost *)connection;
- (void)removeHost:(CKHost *)connection;

- (NSArray *)connections;

- (NSMenu *)menu;

- (NSArray *)allHosts;
- (NSArray *)allCategories;

- (NSArray *)hostsMatching:(NSString *)query;

- (void)setFilterString:(NSString *)filter;
- (void)handleFilterableOutlineView:(NSOutlineView *)view;

- (void)setUsesLeopardStyleSourceList:(BOOL)flag;
- (BOOL)itemIsLeopardSourceGroupHeader:(id)item;
- (NSOutlineView *)outlineView;

@end

extern NSString *CKRegistryChangedNotification;

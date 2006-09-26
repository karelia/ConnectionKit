//
//  CKHostCategory.h
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CKHost;

@interface CKHostCategory : NSObject <NSCoding>
{
	NSString *myName;
	NSMutableArray *myChildCategories;
	NSMutableArray *myHosts;
}

- (id)initWithName:(NSString *)name;
- (NSString *)name;

- (void)addChildCategory:(CKHostCategory *)cat;
- (void)removeChildCategory:(CKHostCategory *)cat;
- (NSArray *)childCategories;

- (void)addHost:(CKHost *)host;
- (void)removeHost:(CKHost *)host;
- (NSArray *)hosts;

- (NSImage *)icon;
- (BOOL)isEditable;

- (id)childAtIndex:(unsigned)index; // returns an object in the concatenated list of cats and dogs... I mean hosts!
- (unsigned)count;
@end

extern NSString *CKHostCategoryChanged;


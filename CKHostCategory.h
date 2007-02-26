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
	
	CKHostCategory *myParentCategory; //not retained
}

- (id)initWithName:(NSString *)name;
- (void)setName:(NSString *)name;
- (NSString *)name;

- (void)addChildCategory:(CKHostCategory *)cat;
- (void)removeChildCategory:(CKHostCategory *)cat;
- (NSArray *)childCategories;

- (void)addHost:(CKHost *)host;
- (void)removeHost:(CKHost *)host;
- (NSArray *)hosts;

- (void)setCategory:(CKHostCategory *)parent;
- (CKHostCategory *)category;

- (NSImage *)icon;
- (BOOL)isEditable;

@end

extern NSString *CKHostCategoryChanged;


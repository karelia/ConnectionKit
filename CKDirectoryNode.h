//
//  CKDirectoryNode.h
//  Connection
//
//  Created by Greg Hulands on 29/08/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKDirectoryNode : NSObject
{
	NSString *myName;
	CKDirectoryNode *myParent; // not retained
	NSMutableArray *myContents;
	NSMutableDictionary *myProperties;
	NSImage *myIcon;
	NSData *myCachedContents;
}

+ (CKDirectoryNode *)nodeWithName:(NSString *)name;
+ (CKDirectoryNode *)nodeForPath:(NSString *)path withRoot:(CKDirectoryNode *)root;
+ (CKDirectoryNode *)addContents:(NSArray *)contents withPath:(NSString *)file withRoot:(CKDirectoryNode *)root;

- (NSString *)name;
- (NSImage *)icon;
- (NSImage *)iconWithSize:(NSSize)size;

- (void)addContent:(CKDirectoryNode *)content;
- (void)addContents:(NSArray *)contents;
- (void)setContents:(NSArray *)contents;
- (void)mergeContents:(NSArray *)contents;
- (NSArray *)contents;

- (unsigned)countIncludingHiddenFiles:(BOOL)flag;
- (NSArray *)contentsIncludingHiddenFiles:(BOOL)flag;
- (NSArray *)filteredContentsWithNamesLike:(NSString *)match includeHiddenFiles:(BOOL)flag;

- (NSString *)kind;
- (unsigned long long)size;
- (BOOL)isDirectory;
- (BOOL)isFilePackage;

- (void)setParent:(CKDirectoryNode *)parent;
- (CKDirectoryNode *)parent;
- (CKDirectoryNode *)root;
- (NSString *)path;

- (void)setProperty:(id)prop forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setProperties:(NSDictionary *)props;
- (NSDictionary *)properties;

- (void)setCachedContents:(NSData *)contents;
- (NSData *)cachedContents;

@end

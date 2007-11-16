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

#import <Cocoa/Cocoa.h>


@interface CKDirectoryNode : NSObject
{
	NSString *myName;
	CKDirectoryNode *myParent; // not retained
	NSMutableArray *myContents;
	NSMutableDictionary *myProperties;
	NSImage *myIcon;
	NSMutableDictionary *myCachedIcons;
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
- (BOOL)isChildOfFilePackage;

- (void)setParent:(CKDirectoryNode *)parent;
- (CKDirectoryNode *)parent;
- (BOOL)isChildOf:(CKDirectoryNode *)node;
- (CKDirectoryNode *)root;
- (NSString *)path;

- (void)setProperty:(id)prop forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setProperties:(NSDictionary *)props;
- (NSDictionary *)properties;

- (void)setCachedContents:(NSData *)contents;
- (NSData *)cachedContents;

@end

extern NSString *CKDirectoryNodeDidRemoveNodesNotification;

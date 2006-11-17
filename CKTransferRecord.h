//
//  CKTransferRecord.h
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CKTransferRecord : NSObject
{
	NSString			*myName;
	unsigned long long	mySize;
	int					myProgress;
	NSMutableArray		*myContents;
	CKTransferRecord	*myParent;
	NSMutableDictionary *myProperties;
}

+ (id)recordWithName:(NSString *)name size:(unsigned long long)size;
- (id)initWithName:(NSString *)name size:(unsigned long long)size;

- (NSString *)name;
- (void)setProgress:(int)progress; 

- (NSNumber *)progress;
- (unsigned long long)size;
- (unsigned long long)transferred;

- (BOOL)isDirectory;

- (void)addContent:(CKTransferRecord *)record;
- (NSArray *)contents;

- (CKTransferRecord *)parent;
- (NSString *)path; 

- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

// Helper methods for working with the recursive data structure

+ (CKTransferRecord *)addFileRecord:(NSString *)file 
							   size:(unsigned long long)size 
						   withRoot:(CKTransferRecord *)root 
						   rootPath:(NSString *)rootPath;
+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forFullPath:(NSString *)path;
+ (CKTransferRecord *)recordForFullPath:(NSString *)path withRoot:(CKTransferRecord *)root;
+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forPath:(NSString *)path;
+ (CKTransferRecord *)recordForPath:(NSString *)path withRoot:(CKTransferRecord *)root;

@end

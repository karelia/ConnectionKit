//
//  CKTransferRecord.h
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Connection/AbstractConnectionProtocol.h>

@interface CKTransferRecord : NSObject
{
	BOOL				isUpload;
	NSString			*myName;
	unsigned long long	mySize;
	unsigned long long  myTransferred;
	unsigned long long  myIntermediateTransferred;
	NSTimeInterval		myLastTransferTime;
	double				mySpeed;
	int					myProgress;
	NSMutableArray		*myContents;
	CKTransferRecord	*myParent; //not retained
	NSMutableDictionary *myProperties;
	
	id <AbstractConnectionProtocol> myConnection; //not retained
	NSError				*myError;
}

+ (id)recordWithName:(NSString *)name size:(unsigned long long)size;
- (id)initWithName:(NSString *)name size:(unsigned long long)size;

- (BOOL)isUpload;

- (NSString *)name;
- (void)setName:(NSString *)name;
- (void)setProgress:(int)progress; 

- (void)cancel:(id)sender;

- (NSNumber *)progress;
- (unsigned long long)size;
- (unsigned long long)transferred;
- (double)speed; // bytes per second
- (BOOL)hasError;
- (NSError *)error;

- (id <AbstractConnectionProtocol>)connection;

- (BOOL)isDirectory;

- (void)addContent:(CKTransferRecord *)record;
- (NSArray *)contents;

- (CKTransferRecord *)root;
- (CKTransferRecord *)parent;
- (NSString *)path; 

- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

/* backward compatibility with NSDictionary */
- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)key;

// Helper methods for working with the recursive data structure

+ (CKTransferRecord *)rootRecordWithPath:(NSString *)path;
+ (CKTransferRecord *)addFileRecord:(NSString *)file 
							   size:(unsigned long long)size 
						   withRoot:(CKTransferRecord *)root 
						   rootPath:(NSString *)rootPath;
+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forFullPath:(NSString *)path;
+ (CKTransferRecord *)recordForFullPath:(NSString *)path withRoot:(CKTransferRecord *)root;
+ (CKTransferRecord *)recursiveRecord:(CKTransferRecord *)record forPath:(NSString *)path;
+ (CKTransferRecord *)recordForPath:(NSString *)path withRoot:(CKTransferRecord *)root;
+ (void)mergeRecord:(CKTransferRecord *)record withRoot:(CKTransferRecord *)root;
+ (void)mergeTextPathRecord:(CKTransferRecord *)record withRoot:(CKTransferRecord *)root;

- (BOOL)problemsTransferringCountingErrors:(int *)outErrors successes:(int *)outSuccesses;

@end

extern NSString *CKTransferRecordProgressChangedNotification;

@interface CKTransferRecord (Private)
- (void)setConnection:(id <AbstractConnectionProtocol>)connection; 
- (void)setSpeed:(double)bps;
- (void)setError:(NSError *)error;
- (void)setUpload:(BOOL)flag;
- (void)setSize:(unsigned long long)size;
- (BOOL)isLeaf;
@end
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


@protocol AbstractConnectionProtocol;


@interface CKTransferRecord : NSObject
{
	BOOL _isUpload;
	NSString *_name;
	unsigned long long _size;
	unsigned long long _transferred;
	unsigned long long _intermediateTransferred;
	NSTimeInterval _lastTransferTime;
	NSTimeInterval _transferStartTime;
	NSTimeInterval _lastDirectorySpeedUpdate;
	float _speed;
	NSUInteger _progress;
	NSMutableArray *_contents;
	CKTransferRecord *_parent; //not retained
	NSMutableDictionary *_properties;
	
	id <AbstractConnectionProtocol> _connection; //not retained
	NSError *_error;
}

- (BOOL)isUpload;
- (void)setUpload:(BOOL)flag;

- (NSString *)name;
- (void)setName:(NSString *)name;

- (unsigned long long)size;
- (void)setSize:(unsigned long long)size;

- (float)speed;
- (void)setSpeed:(float)speed;	// TODO: Switch to CGFloat

- (NSError *)error;

- (id <AbstractConnectionProtocol>)connection;
- (void)setConnection:(id <AbstractConnectionProtocol>)connection;	// Weak ref

- (CKTransferRecord *)parent;
- (void)setParent:(CKTransferRecord *)parent;	// Weak ref


+ (id)recordWithName:(NSString *)name size:(unsigned long long)size;
- (id)initWithName:(NSString *)name size:(unsigned long long)size;
- (void)cancel:(id)sender;

- (BOOL)isDirectory;
- (unsigned long long)transferred;
- (NSInteger)progress;
- (void)setProgress:(NSInteger)progress;

- (void)addContent:(CKTransferRecord *)record;
- (NSArray *)contents;

- (BOOL)hasError;

- (CKTransferRecord *)root;
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
extern NSString *CKTransferRecordTransferDidBeginNotification;
extern NSString *CKTransferRecordTransferDidFinishNotification;

@interface CKTransferRecord (Private)
- (void)setConnection:(id <AbstractConnectionProtocol>)connection; 
- (void)setSpeed:(double)bps;
- (void)setError:(NSError *)error;
- (void)setUpload:(BOOL)flag;
- (void)setSize:(unsigned long long)size;
- (BOOL)isLeaf;
@end
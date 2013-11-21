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


#import <Foundation/Foundation.h>


@class CK2FileOperation;
@interface CKTransferRecord : NSObject
{
	NSString *_name;
    CK2FileOperation    *_operation;
    int64_t             _size;
	NSTimeInterval _lastTransferTime;
	NSTimeInterval _transferStartTime;
	NSTimeInterval _lastDirectorySpeedUpdate;
	CGFloat _speed;
	NSMutableArray *_contents;
	CKTransferRecord *_parent; //not retained
	NSMutableDictionary *_properties;
	    
    void *_observationInfo;
}

- (NSString *)name;
- (void)setName:(NSString *)name;

@property(readonly) int64_t size;

- (CGFloat)speed;
- (void)setSpeed:(CGFloat)speed;	// TODO: Switch to CGFloat

- (BOOL)isFinished;
- (NSError *)error;

- (CKTransferRecord *)parent;

+ (instancetype)recordWithName:(NSString *)name uploadOperation:(CK2FileOperation *)operation;
- (id)initWithName:(NSString *)name uploadOperation:(CK2FileOperation *)operation;

@property(nonatomic, retain, readonly) CK2FileOperation *uploadOperation;

- (BOOL)isDirectory;
- (unsigned long long)transferred;

/**
 Between 0 and 100.
 */
@property(readonly) CGFloat progress;

- (NSDictionary *)nameWithProgressAndFileSize;

- (void)addContent:(CKTransferRecord *)record;
- (NSArray *)contents;

- (CKTransferRecord *)root;
- (NSString *)path; 

- (void)setProperty:(id)property forKey:(NSString *)key __attribute((nonnull(2)));
- (id)propertyForKey:(NSString *)key;

/* backward compatibility with NSDictionary */
- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)key;

// Helper methods for working with the recursive data structure

+ (CKTransferRecord *)rootRecordWithPath:(NSString *)path;

// If the path is absolute, searches from root of tree, otherwise searches from receiver
- (CKTransferRecord *)recordForPath:(NSString *)path;

- (BOOL)problemsTransferringCountingErrors:(NSInteger *)outErrors successes:(NSInteger *)outSuccesses;

@end

extern NSString *CKTransferRecordTransferDidBeginNotification;
extern NSString *CKTransferRecordTransferDidFinishNotification;


#pragma mark -


@interface NSObject (CKConnectionTransferDelegate)
- (void)transferDidBegin:(CKTransferRecord *)transfer;
- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length;
- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error;
- (void)transferDidFinish:(CKTransferRecord *)transfer error:(NSError *)error;
@end


#pragma mark -


@interface CKTransferRecord (Private)
- (void)setSpeed:(double)bps;
- (void)setUpload:(BOOL)flag;
- (BOOL)isLeaf;
@end

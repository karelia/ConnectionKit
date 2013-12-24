//
//  CK2Transcript.h
//  Connection
//
//  Created by Mike on 24/12/2013.
//
//

#import <Foundation/Foundation.h>


/**
 All safe to access from multiple threads. Be a bit wary that new entries might
 arrive while removing existing ones though, if you have any UI code around it.
 */


@interface CK2TranscriptEntry : NSObject
{
  @private
    NSString    *_text;
    BOOL        _isCommand;
}

@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, readonly) BOOL isCommand;

@end


@interface CK2Transcript : NSObject
{
  @private
    NSMutableArray      *_entries;
    dispatch_queue_t    _queue;
}

#pragma mark Shared Transcript
+ (CK2Transcript *)sharedTranscript;


#pragma mark Retrieving Entries
- (NSArray *)entries;
- (NSUInteger)countOfEntries;
- (CK2TranscriptEntry *)entryAtIndex:(NSUInteger)index;


#pragma mark Adding Entries
- (void)addEntryWithText:(NSString *)text isCommand:(BOOL)command;


#pragma mark Removing Entries
- (void)removeAllEntries;


@end


/**
 Posted on whichever thread modified the transcript
 */
extern NSString * const CK2TranscriptChangedNotification;


/**
 Key in `CK2TranscriptChangedNotification`'s `userInfo` for the entry (if there
 was one) that was added.
 */
extern NSString * const CK2TranscriptAddedEntryKey;


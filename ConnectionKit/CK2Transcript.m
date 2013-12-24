//
//  CK2Transcript.m
//  Connection
//
//  Created by Mike on 24/12/2013.
//
//

#import "CK2Transcript.h"


@implementation CK2TranscriptEntry

- initWithText:(NSString *)text type:(NSString *)type;
{
    if (self = [self init])
    {
        _text = [text copy];
        _type = [type copy];
    }
    return self;
}

- (void)dealloc;
{
    [_text release];
    [_type release];
    
    [super dealloc];
}

@synthesize text = _text;
@synthesize entryType = _type;

@end


@implementation CK2Transcript

+ (CK2Transcript *)sharedTranscript;
{
    static CK2Transcript *transcript;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        transcript = [[CK2Transcript alloc] init];
    });
    return transcript;
}

- init
{
    if (self = [super init])
    {
        _entries = [[NSMutableArray alloc] init];
        _queue = dispatch_queue_create("com.karelia.ConnectionKit.transcript", NULL);
    }
    return self;
}

- (void)dealloc;
{
    [_entries release];
    dispatch_release(_queue);
    
    [super dealloc];
}

- (NSArray *)entries;
{
    __block NSArray *result;
    dispatch_sync(_queue, ^{
        result = [_entries copy];
    });
    return [result autorelease];
}

- (NSUInteger)countOfEntries;
{
    __block NSUInteger result;
    dispatch_sync(_queue, ^{
        result = _entries.count;
    });
    return result;
}

- (CK2TranscriptEntry *)entryAtIndex:(NSUInteger)index;
{
    __block CK2TranscriptEntry *result;
    dispatch_sync(_queue, ^{
        result = [[_entries objectAtIndex:index] retain];
    });
    return [result autorelease];
}

- (void)addEntryOfType:(NSString *)type text:(NSString *)text;
{
    dispatch_async(_queue, ^{
        CK2TranscriptEntry *entry = [[CK2TranscriptEntry alloc] initWithText:text type:type];
        [_entries addObject:entry];
        [entry release];
    });
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CK2TranscriptChangedNotification object:self];
}

- (void)removeAllEntries;
{
    dispatch_async(_queue, ^{
        [_entries removeAllObjects];
    });
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CK2TranscriptChangedNotification object:self];
}

@end


NSString * const CK2TranscriptChangedNotification = @"CK2TranscriptChanged";

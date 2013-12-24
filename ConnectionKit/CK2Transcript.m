//
//  CK2Transcript.m
//  Connection
//
//  Created by Mike on 24/12/2013.
//
//

#import "CK2Transcript.h"


@implementation CK2TranscriptEntry

- initWithText:(NSString *)text isCommand:(BOOL)isCommand;
{
    if (self = [self init])
    {
        _text = [text copy];
        _isCommand = isCommand;
    }
    return self;
}

- (void)dealloc;
{
    [_text release];
    [super dealloc];
}

@synthesize text = _text;
@synthesize isCommand = _isCommand;

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

- (void)addEntryWithText:(NSString *)text isCommand:(BOOL)command;
{
    CK2TranscriptEntry *entry = [[CK2TranscriptEntry alloc] initWithText:text isCommand:command];
    
    dispatch_async(_queue, ^{
        
        if (!_entries)
        {
            _entries = [[NSMutableArray alloc] init];
            
            // Start off with details of the host machine
            NSBundle *bundle = [NSBundle mainBundle];
            NSString *transcriptHeader = [NSString stringWithFormat:
                                          @"%@ %@ (architecture unknown) Session Transcript [%@] (%@)",
                                          [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey],
                                          [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey],
                                          [[NSProcessInfo processInfo] operatingSystemVersionString],
                                          [NSDate date]];
            
            CK2TranscriptEntry *entry = [[CK2TranscriptEntry alloc] initWithText:transcriptHeader isCommand:NO];
            [_entries addObject:entry];
            [entry release];
        }
        
        [_entries addObject:entry];
    });
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CK2TranscriptChangedNotification
                                                        object:self
                                                      userInfo:@{ CK2TranscriptAddedEntryKey : entry }];
    
    [entry release];
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
NSString * const CK2TranscriptAddedEntryKey = @"entry";

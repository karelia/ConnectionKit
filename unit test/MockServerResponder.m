// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import "MockServerResponder.h"
#import "MockServer.h"

@interface MockServerResponder()

@property (strong, nonatomic) NSArray* requests;
@property (strong, nonatomic) NSArray* responses;
@property (strong, nonatomic, readwrite) NSArray* initialResponse;

@end

@implementation MockServerResponder

@synthesize initialResponse = _initialResponse;
@synthesize requests = _requests;
@synthesize responses = _responses;

#pragma mark - Object Lifecycle

+ (MockServerResponder*)responderWithResponses:(NSArray *)responses
{
    MockServerResponder* server = [[MockServerResponder alloc] initWithResponses:responses];

    return [server autorelease];
}

- (id)initWithResponses:(NSArray *)responses
{
    if ((self = [super init]) != nil)
    {
        // process responses array - we pull out some special responses, and pre-calculate all the regular expressions
        NSRegularExpressionOptions options = NSRegularExpressionDotMatchesLineSeparators;
        NSMutableArray* processed = [NSMutableArray arrayWithCapacity:[responses count]];
        NSMutableArray* expressions = [NSMutableArray arrayWithCapacity:[responses count]];
        for (NSArray* response in responses)
        {
            NSUInteger length = [response count];
            if (length > 0)
            {
                NSString* key = response[0];
                NSArray* commands = [response subarrayWithRange:NSMakeRange(1, length - 1)];
                if ([key isEqualToString:InitialResponseKey])
                {
                    self.initialResponse = commands;
                }
                else
                {
                    NSError* error = nil;
                    NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:key options:options error:&error];
                    if (expression)
                    {
                        [expressions addObject:expression];
                        [processed addObject:commands];
                    }
                }
            }
        }
        self.requests = expressions;
        self.responses = processed;
    }

    return self;
}

- (void)dealloc
{
    [_initialResponse release];
    [_responses release];
    [_requests release];
    
    [super dealloc];
}

#pragma mark - Public API

- (NSArray*)responseForRequest:(NSString *)request server:(MockServer *)server
{
    NSArray* commands = nil;
    NSRange wholeString = NSMakeRange(0, [request length]);

    MockServerLog(@"got request '%@'", request);

    BOOL matched = NO;
    NSUInteger count = [self.requests count];
    for (NSUInteger n = 0; n < count; ++n)
    {
        NSRegularExpression* expression = self.requests[n];
        NSTextCheckingResult* match = [expression firstMatchInString:request options:0 range:wholeString];
        if (match)
        {
            MockServerLog(@"matched with request pattern %@", expression);
            NSArray* rawCommands = self.responses[n];
            commands = [self substitutedCommands:rawCommands match:match request:request];
            matched = YES;
            break;
        }
    }

    return commands;
}

- (void)addSubstitutionsForMatch:(NSTextCheckingResult*)match request:(NSString*)request toDictionary:(NSMutableDictionary*)dictionary
{
    // always add the request as $0
    [dictionary setObject:request forKey:@"$0"];

    // add any matched subgroups
    if (match)
    {
        NSUInteger count = match.numberOfRanges;
        for (NSUInteger n = 1; n < count; ++n)
        {
            NSString* token = [NSString stringWithFormat:@"$%ld", (long) n];
            NSRange range = [match rangeAtIndex:n];
            NSString* replacement = [request substringWithRange:range];
            [dictionary setObject:replacement forKey:token];
        }
    }
}

- (NSString*)substitutedCommand:(NSString*)command match:(NSTextCheckingResult*)match request:(NSString*)request
{
    return command;
}

- (NSArray*)substitutedCommands:(NSArray*)commands match:(NSTextCheckingResult*)match request:(NSString*)request
{
    NSMutableDictionary* substitutions = [NSMutableDictionary dictionary];
    [self addSubstitutionsForMatch:match request:request toDictionary:substitutions];

    NSMutableArray* substitutedCommands = [NSMutableArray arrayWithCapacity:[commands count]];
    for (id command in commands)
    {
        if ([command isKindOfClass:[NSString class]])
        {
            BOOL containsTokens = [command rangeOfString:@"$"].location != NSNotFound;
            if (containsTokens)
            {
                NSMutableString* substituted = [NSMutableString stringWithString:command];
                [substitutions enumerateKeysAndObjectsUsingBlock:^(id key, id replacement, BOOL *stop) {
                    [substituted replaceOccurrencesOfString:key withString:replacement options:0 range:NSMakeRange(0, [substituted length])];
                }];

                command = substituted;
                MockServerLog(@"expanded response %@ as %@", command, substituted);
            }
        }

        [substitutedCommands addObject:command];
    }

    return substitutedCommands;
}

@end

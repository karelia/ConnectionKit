//
//  CK2TrampolineAuthenticationChallenge.m
//  Connection
//
//  Created by Mike on 10/07/2013.
//
//

#import "CK2TrampolineAuthenticationChallenge.h"

@implementation CK2TrampolineAuthenticationChallenge

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge sender:(id<NSURLAuthenticationChallengeSender>)sender;
{
    if (self = [super initWithAuthenticationChallenge:challenge sender:sender])
    {
        _originalChallenge = [challenge retain];
    }
    
    return self;
}

- (void)dealloc;
{
    [_originalChallenge release];
    [super dealloc];
}

@synthesize originalChallenge = _originalChallenge;

@end

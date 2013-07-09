//
//  NSObject+CK2OpenPanel.m
//  Connection
//
//  Created by Paul Kim on 4/16/13.
//
//

#import "NSObject+CK2OpenPanel.h"

@implementation NSObject (CK2OpenPanel)

+ (void)ck2_invokeBlockOnMainThread:(void (^)())block
{
    [[[block copy] autorelease] performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO modes:@[ NSRunLoopCommonModes ]];
}

- (void)ck2_invoke
{
    ((void (^)())self)();
}

@end

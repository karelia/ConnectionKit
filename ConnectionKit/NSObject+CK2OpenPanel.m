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
    NSOperation *op = [NSBlockOperation blockOperationWithBlock:block];
    
    [op performSelectorOnMainThread:@selector(start)
                         withObject:nil
                      waitUntilDone:NO
                              modes:@[ NSRunLoopCommonModes ]];
}

@end

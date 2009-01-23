//
//  NSInvocation+ConnectionKit.m
//  Connection
//
//  Created by Mike on 22/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "NSInvocation+ConnectionKit.h"


@implementation NSInvocation (ConnectionKit)

+ (NSInvocation *)invocationWithTarget:(id)aTarget selector:(SEL)aSelector arguments:(NSArray *)anArgumentArray
{
    NSMethodSignature *methodSignature = [aTarget methodSignatureForSelector:aSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    if ( nil != invocation )
    {
        [invocation setSelector:aSelector];
		if (nil != aTarget)
		{
			[invocation setTarget:aTarget];
		}
        if ( (nil != anArgumentArray) && ([anArgumentArray count] > 0) )
        {
            NSEnumerator *e = [anArgumentArray objectEnumerator];
            id argument;
            int argumentIndex = 2; // arguments start at index 2 per NSInvocation.h
            while ( argument = [e nextObject] )
            {
                if ( [argument isMemberOfClass:[NSNull class]] )
                {
                    [invocation setArgument:nil atIndex:argumentIndex];
                }
                else
                {
                    [invocation setArgument:&argument atIndex:argumentIndex];
                }
                argumentIndex++;
            }
            [invocation retainArguments];
        }
    }
	
    return invocation;
}

+ (NSInvocation *)invocationWithTarget:(id)aTarget selector:(SEL)aSelector
{
    NSInvocation *result = [self invocationWithMethodSignature:[aTarget methodSignatureForSelector:aSelector]];
    [result setTarget:aTarget];
    [result setSelector:aSelector];
    
    return result;
}

@end

//
//  NSInvocation+Connection.m
//  Connection
//
//  Created by Sam Deane on 02/07/2012.
//
//

#import "NSInvocation+Connection.h"

@implementation NSInvocation (Connection)

+ (NSInvocation *)invocationWithSelector:(SEL)aSelector target:(id)aTarget arguments:(NSArray *)anArgumentArray
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

@end

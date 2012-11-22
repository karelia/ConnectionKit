//
//  NSInvocation+Connection.h
//  Connection
//
//  Created by Sam Deane on 02/07/2012.
//
//

#import <Foundation/Foundation.h>

@interface NSInvocation (Connection)

+ (NSInvocation *)invocationWithSelector:(SEL)aSelector
								  target:(id)aTarget
							   arguments:(NSArray *)anArgumentArray;
@end

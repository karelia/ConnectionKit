//
//  NSObject+CK2OpenPanel.h
//  Connection
//
//  Created by Paul Kim on 4/16/13.
//
//

#import <Foundation/Foundation.h>

@interface NSObject (CK2OpenPanel)

+ (void)ck2_invokeBlockOnMainThread:(void (^)())block;

@end

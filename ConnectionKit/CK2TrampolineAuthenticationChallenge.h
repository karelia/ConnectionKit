//
//  CK2TrampolineAuthenticationChallenge.h
//  Connection
//
//  Created by Mike on 10/07/2013.
//
//

#import <Foundation/Foundation.h>

@interface CK2TrampolineAuthenticationChallenge : NSURLAuthenticationChallenge
{
  @private
    NSURLAuthenticationChallenge *_originalChallenge;
}

@property(readonly) NSURLAuthenticationChallenge *originalChallenge;

@end

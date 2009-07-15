//
//  CK_AsyncOperation.h
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface CK_AsyncOperation : NSOperation
{
  @private  
    BOOL    _isFinished;
    BOOL    _isExecuting;
}

- (void)operationDidFinish;

@end

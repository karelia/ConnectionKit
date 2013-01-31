//
//  CK2IconView.h
//  Connection
//
//  Created by Paul Kim on 1/17/13.
//
//

#import <Cocoa/Cocoa.h>

@interface CK2IconView : NSCollectionView
{
    NSMutableString     *_typeSelectBuffer;
    NSTimer             *_typeSelectTimer;
    
    BOOL                _messageMode;
    NSURL               *_homeURL;
}

@property (readwrite, assign, nonatomic) BOOL   messageMode;
@property (readwrite, copy) NSURL               *homeURL;


@end

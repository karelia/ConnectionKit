//
//  CK2BrowserPreviewControllerViewController.m
//  CKTest
//
//  Created by Paul Kim on 12/26/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
//

#import "CK2BrowserPreviewController.h"
#import "CK2BrowserPreviewView.h"
#import "NSURL+CK2OpenPanel.h"

@implementation CK2BrowserPreviewController

- (id)init;
{
    if ((self = [super initWithNibName:@"CK2FilePreview" bundle:[NSBundle bundleForClass:[self class]]]) != nil)
    {
    }
    
    return self;
}

- (void)loadView
{
    [super loadView];
}

- (void)setRepresentedObject:(id)representedObject
{
    [super setRepresentedObject:representedObject];
    
    [(CK2BrowserPreviewView *)[self view] setURL:representedObject];
}

@end

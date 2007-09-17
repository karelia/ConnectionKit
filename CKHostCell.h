//
//  CKHostCell.h
//  Connection
//
//  Created by Greg Hulands on 20/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/*
 
 Outline views that use the ConnectionRegistry as it's datasource need to have it's single colum 
 data cell as a CKHostCell. This is a modified version of Omni's cell class

 */
@interface CKHostCell : NSTextFieldCell 
{
	NSImage *myIcon;
	struct {
        unsigned int drawsHighlight:1;
        unsigned int imagePosition:3;
        unsigned int settingUpFieldEditor:1;
    } myFlags;
}

- (NSImage *)icon;
- (void)setIcon:(NSImage *)anIcon;

- (NSCellImagePosition)imagePosition;
- (void)setImagePosition:(NSCellImagePosition)aPosition;

- (BOOL)drawsHighlight;
- (void)setDrawsHighlight:(BOOL)flag;

- (NSRect)textRectForFrame:(NSRect)cellFrame inView:(NSView *)controlView;

@end

extern NSString *CKHostCellStringValueKey;
extern NSString *CKHostCellSecondaryStringValueKey;
extern NSString *CKHostCellImageValueKey;

@interface CKHostExtendedCell : CKHostCell
{
	NSString *mySecondaryString;
}

- (void)setSecondaryString:(NSString *)str;
- (NSString *)secondaryString;

@end

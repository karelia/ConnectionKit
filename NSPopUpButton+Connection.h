//
//  NSPopUpButton+Connection.h
//  Connection
//
//  Created by Greg Hulands on 29/08/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSPopUpButton (Connection)

- (void)selectItemWithRepresentedObject:(id)representedObject;
- (id)representedObjectOfSelectedItem;

@end

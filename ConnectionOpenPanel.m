/*
 Copyright (c) 2006, Greg Hulands <ghulands@framedphotographics.com>
 All rights reserved.
 
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */


#import "ConnectionOpenPanel.h"

@interface ConnectionNode : NSObject
{
	NSDictionary *myAttributes;
	NSMutableArray *myContents;
}

+ (id)nodeWithAttributes:(NSDictionary *)attribs;

- (BOOL)isLeaf;

- (void)addItem:(ConnectionNode *)item;
- (NSArray *)items;

@end


@implementation ConnectionOpenPanel

+ (id)openPanelToHost:(NSString *)host port:(NSString *)port connectionType:(NSString *)type username:(NSString *)username password:(NSString *)password
{
	if (!host)
		@throw [NSException exceptionWithName:NSInvalidArgumentException
									   reason:@"host is nil"
									 userInfo:nil];
	if (!port && !type)
		@throw [NSException exceptionWithName:NSInvalidArgumentException
									   reason:@"port or type must be specified"
									 userInfo:nil];
}

- (void)setCanChooseFiles:(BOOL)flag
{
	myFlags.canChooseFiles = flag;
	
}

- (void)setCanChooseFolders:(BOOL)flag
{
	myFlags.canChooseFolders = flag;
}

- (BOOL)canChooseFiles
{
	return myFlags.canChooseFiles;
}

- (BOOL)canChooseFolders
{
	return myFlags.canChooseFiles;
}

- (NSArray *)filenames
{
	return [NSArray arrayWithArray:mySelection];
}

- (IBAction)cancel:(id)sender
{
	[[NSApplication sharedApplication] endSheet:self returnCode:NSCancelButton];
	[self orderOut:sender];
}

- (IBAction)choose:(id)sender
{
	[[NSApplication sharedApplication] endSheet:self returnCode:NSOKButton];
	[self orderOut:sender];
}

#pragma mark -
#pragma mark NSBrowser Delegate Methods

- (ConnectionNode *)nodeAtColumn:(int)column
{
	
}

- (ConnectionNode *)nodeAtColumn:(int)column row:(int)row
{
	if (column == 0)
	{
		return [myRoot objectAtIndex:row];
	}
	return [[[self nodeAtColumn:column] items] objectAtIndex:row];
}

- (int)browser:(NSBrowser *)sender numberOfRowsInColumn:(int)column
{
	if (column == 0)
	{
		[myRoot count];
	}
	else
	{
		return [[[self nodeAtColumn:column] items] count];
	}
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(int)row column:(int)column
{
	ConnectionNode *node = [self nodeAtColumn:column row:row];
	[cell setStringValue:[node attributeForKey:cxFilenameKey]];
	if ([[node attributeForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
	{
		if (myFlags.canChooseFolders)
		{
			[cell setState:NSOnState];
		}
		else
		{
			[cell setState:NSOffState];
		}
	}
	else
	{
		// we are a file of some type
		if (myFlags.canChooseFiles)
		{
			[cell setState:NSOnState];
		}
		else
		{
			[cell setState:NSOffState];
		}
	}
}

@end


@implementation ConnectionNode
{
	NSDictionary *myAttributes;
	NSMutableArray *myContents;
}

- (id)initWithAttributes:(NSDictionary *)attribs
{
	if (self = [super init])
	{
		myAttributes = [attribs retain];
		myContents = [[NSMutableArray array] retain];
	}
	return self;
}

- (void)dealloc
{
	[myAttributes release];
	[myContents release];
	[super dealloc];
}

+ (id)nodeWithAttributes:(NSDictionary *)attribs
{
	return [[[ConnectionNode alloc] initWithAttributes:attribs] autorelease];
}

- (BOOL)isLeaf
{
	return [myContents count] == 0;
}

- (void)addItem:(ConnectionNode *)item
{
	[myContents addObject:item];
}

- (NSArray *)items
{
	return [NSArray arrayWithArray:myContents];
}

@end
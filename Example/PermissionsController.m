#import "PermissionsController.h"

static PermissionsController *_shared = nil;

@implementation PermissionsController

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"Permissions" owner:self];
	return self;
}

+ (id)sharedPermissions
{
	if (!_shared)
		_shared = [[PermissionsController alloc] init];
	return _shared;
}

- (void)displayFile:(NSMutableDictionary *)file sheet:(NSWindow *)win connection:(id)con
{
	_con = con;
	
	NSNumber *posix = [file objectForKey:NSFilePosixPermissions];
	NSLog(@"%@: %@", NSStringFromSelector(_cmd), posix);
	
	[NSApp beginSheet:window
	   modalForWindow:win
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
}

- (IBAction)attribsChanged:(id)sender
{
	_needsUpdating = YES;
}

- (IBAction)cancel:(id)sender
{
	[window orderOut:self];
	[NSApp endSheet:window];
}

- (IBAction)save:(id)sender
{
	if (_needsUpdating)
	{
	//	[_con setPermissions: forFile:];
	}
	[self cancel:self];
}

@end

/* KTLogController */

#import <Cocoa/Cocoa.h>

@interface KTLogController : NSObject
{
    IBOutlet NSTableView *oTable;
    IBOutlet NSWindow *oWindow;
	
	NSArray *myEntries;
}
@end

/* PermissionsController */

#import <Cocoa/Cocoa.h>

@interface PermissionsController : NSObject
{
    IBOutlet id ge;
    IBOutlet id gr;
    IBOutlet id gw;
    IBOutlet id ue;
    IBOutlet id ur;
    IBOutlet id uw;
    IBOutlet id we;
    IBOutlet id window;
    IBOutlet id wr;
    IBOutlet id ww;
	
	BOOL _needsUpdating;
	id _con;
}
+ (id)sharedPermissions;

- (void)displayFile:(NSMutableDictionary *)file sheet:(NSWindow *)win connection:(id)con;

- (IBAction)attribsChanged:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)save:(id)sender;
@end

#import <Cocoa/Cocoa.h>
@class CKSFTPConnection;

@protocol CKSFTPTServerInterface
- (void)connectToServerWithArguments:(NSArray *)arguments forWrapperConnection:(CKSFTPConnection *)sftpWrapperConnection;
@end

typedef enum
{
	SFTPListingShortForm = 0,
	SFTPListingLongForm,
	SFTPListingExtendedLongForm,
	SFTPListingUnsupported
} SFTPListingForm;

@interface CKSFTPTServer : NSObject <CKSFTPTServerInterface>
{
    NSMutableArray *directoryContents;
	NSMutableString *directoryListingBufferString;

	//Core
	int master;
	pid_t sftppid;
	//Flags
	BOOL cancelflag;
	BOOL connecting;
	BOOL connected;
}
- (void)forceDisconnect;

//! @abstract Returns the listing form that can be used on the current system.
+ (SFTPListingForm)SFTPListingForm;
@end

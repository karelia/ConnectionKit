#import <Cocoa/Cocoa.h>
@class CKSFTPConnection;

@protocol CKSFTPTServerInterface
- (void)connectToServerWithArguments:(NSArray *)arguments forWrapperConnection:(CKSFTPConnection *)sftpWrapperConnection;
@end

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
@end

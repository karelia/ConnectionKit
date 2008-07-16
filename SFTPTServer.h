#import <Cocoa/Cocoa.h>
@class SFTPConnection;

@protocol SFTPTServerInterface
- (oneway void)connectToServerWithArguments:(NSArray *)arguments forWrapperConnection:(SFTPConnection *)sftpWrapperConnection;
@end

@interface SFTPTServer : NSObject <SFTPTServerInterface>
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

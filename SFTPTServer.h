/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>
@class SFTPConnection;

@protocol SFTPTServerInterface

- (oneway void)connectToServerWithParams:(NSArray *)params fromWrapperConnection:(SFTPConnection *)sftpWrapperConnection;
- ( int )atSftpPrompt;
- ( pid_t )getSftpPid;

@end

@interface SFTPTServer : NSObject <SFTPTServerInterface> {
@private
    int			atprompt;
    NSString		*remoteDirBuf;
    NSString		*_currentTransferPath;
    NSString            *_sftpRemoteObjectList;
	NSMutableString *directoryListingBufferString;
	
	int		cancelflag;
	pid_t		sftppid;
	BOOL connecting;
	int		connected;
	int		master;
}

+ ( void )connectWithPorts: ( NSArray * )ports;
- ( id )init;
- (void)forceDisconnect;
- ( NSString * )retrieveUnknownHostKeyFromStream: ( FILE * )stream;
- ( NSMutableDictionary * )remoteObjectFromSFTPLine: ( char * )line;
- ( BOOL )hasDirectoryListingFormInBuffer: ( char * )buf;
- ( void )collectListingFromMaster: ( int )master fileStream: ( FILE * )mf forWrapperConnection: ( SFTPConnection * )wrapperConn;
- (NSString *)currentTransferPath;

@end

//
//  CKConnectionClient.h
//  Connection
//
//  Created by Mike on 15/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKConnectionClientProtocol.h"


@class CKAbstractConnection;


typedef struct __flags {
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	
	unsigned permissions:1;
	unsigned cancel:1; // deprecated
	unsigned didCancel:1;
	unsigned changeDirectory:1;
	unsigned createDirectory:1;
	unsigned deleteDirectory:1;
	unsigned deleteDirectoryInAncestor:1;
	unsigned deleteFileInAncestor:1;
	unsigned discoverFilesToDeleteInAncestor:1;
	unsigned discoverFilesToDeleteInDirectory:1;
	unsigned deleteFile:1;
	unsigned didBeginUpload:1;
	unsigned didConnect:1;
	unsigned didDisconnect:1;
	unsigned directoryContents:1;
	unsigned didBeginDownload:1;
	unsigned downloadFinished:1;
	unsigned downloadPercent:1;
	unsigned downloadProgressed:1;
	unsigned error:1;
	unsigned rename:1;
	unsigned uploadFinished:1;
	unsigned uploadPercent:1;
	unsigned uploadProgressed:1;
	unsigned directoryContentsStreamed:1;
	unsigned fileCheck:1;
	unsigned authorizeConnection:1;
    unsigned cancelAuthorization:1;
	unsigned isRecursiveDeleting:1;
	unsigned passphrase:1;
	unsigned transcript:1;
	
	unsigned padding:2;
} CKConnectionDelegateFlags;


@class RunLoopForwarder;


@interface CKConnectionClient : NSObject <CKConnectionClient, NSURLAuthenticationChallengeSender>
{
@private
    CKAbstractConnection        *_connection;    // Weak ref
    CKConnectionDelegateFlags   _flags;
    RunLoopForwarder            *_forwarder;
    
    // Authentication
    NSURLAuthenticationChallenge    *_currentAuthenticationChallenge;
    NSURLAuthenticationChallenge    *_originalAuthenticationChallenge;
    NSThread                        *_authenticationThread;
}

- (id)initWithConnection:(CKAbstractConnection *)connection;
- (CKAbstractConnection *)connection;

- (void)setDelegate:(id)delegate;

@end

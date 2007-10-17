/*
 Copyright (c) 2005, Greg Hulands <ghulands@mac.com>
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

#import <Foundation/Foundation.h>
#import <Connection/AbstractQueueConnection.h>
#import <Security/SecureTransport.h>
#import <Security/Security.h>

/*
 *	A Stream Based Connection runs the streams in a background thread and handles the
 *	delegate notifications of the streams.
 *
 *	Properties used:
 *		FileCheckingTranscript
 *
 */
@protocol OutputStream, InputStream;

@interface StreamBasedConnection : AbstractQueueConnection 
{
	NSThread			*_createdThread;
	
	id<OutputStream>	_sendStream;
	id<InputStream>		_receiveStream;
	BOOL				_isForceDisconnecting;
	
	NSMutableData		*_sendBuffer;
	NSLock				*_sendBufferLock;
	
	// speed support
	NSTimeInterval		_lastChunkSent;
	NSTimeInterval		_lastChunkReceived;
	double				_uploadSpeed;
	double				_downloadSpeed;
	
	// This is a peer connection that is used to check if files exist
	id <AbstractConnectionProtocol>	_fileCheckingConnection;
	NSLock							*_fileCheckLock;
	NSString						*_fileCheckInFlight;
	
	// These peer connections are used to speed up recursive directory deletion
	NSMutableArray					*_recursiveDeletionsQueue;
	id <AbstractConnectionProtocol> _recursiveListingConnection;
	id <AbstractConnectionProtocol> _recursiveDeletionConnection;
	unsigned						_numberOfListingsRemaining;
	unsigned						_numberOfDeletionsRemaining;
	unsigned						_numberOfDirDeletionsRemaining;
	NSMutableArray					*_emptyDirectoriesToDelete;
	NSLock							*_deletionLock;
	
	// Peer connection support for recursive download
	id <AbstractConnectionProtocol> _recursiveDownloadConnection;
	unsigned						_downloadListingsRemaining;
	NSMutableArray					*_recursiveDownloadQueue;
	NSLock							*_recursiveDownloadLock;
	
	struct __streamflags {
		unsigned sendOpen : 1;
		unsigned readOpen : 1;
		unsigned receiveHasBytes : 1;
		unsigned wantsSSL : 1;
		unsigned sslOn : 1;
		unsigned verifySSLCert : 1;
		unsigned allowsBadCerts : 1; // for data transfer connections
		unsigned isNegotiatingSSL : 1;
		unsigned initializedSSL : 1;
		unsigned reportedError : 1;
		unsigned isDeleting: 1;
		unsigned isDownloading: 1;
		unsigned unused: 22;
	} myStreamFlags;
	
	// SSL Support
	SSLContextRef		mySSLContext;
	SecIdentityRef		mySSLIdentity;
	NSMutableData		*mySSLSendBuffer;
	NSMutableData		*mySSLRecevieBuffer;
	NSMutableData		*mySSLRawReadBuffer;
	NSMutableData		*mySSLEncryptedSendBuffer;
}

- (void)openStreamsToPort:(unsigned)port;
- (void)scheduleStreamsOnRunLoop;

- (void)setSendStream:(NSStream *)stream;
- (void)setReceiveStream:(NSStream *)stream;
- (NSStream *)sendStream;
- (NSStream *)receiveStream;
- (void)closeStreams;

- (BOOL)sendStreamOpen;
- (BOOL)receiveStreamOpen;

// subclasses can override
- (void)sendStreamDidOpen;
- (void)sendStreamDidClose;
- (void)receiveStreamDidOpen;
- (void)receiveStreamDidClose;

- (void)handleSendStreamEvent:(NSStreamEvent)theEvent;
- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent;
- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length;
- (void)stream:(id<InputStream>)stream readBytesOfLength:(unsigned)length;

// Get the local command port
- (CFSocketNativeHandle)socket;
- (unsigned)localPort;
- (NSString *)remoteIPAddress;

// Subclass needs to override these methods
- (void)processReceivedData:(NSData *)data;
- (void)sendCommand:(id)command;

- (unsigned)sendData:(NSData *)data; // returns how many bytes it sent. If the buffer was not empty and it was appended, then it will return 0
- (NSData *)availableData;
- (int)availableData:(NSData **)data ofLength:(int)length;

// These are called on the background thread
- (void)threadedConnect;
- (void)threadedDisconnect;
- (void)threadedForceDisconnect;

// SSL Support
- (void)setSSLOn:(BOOL)flag;

@end

extern NSString *StreamBasedErrorDomain;
extern NSString *SSLErrorDomain;

enum { StreamErrorFailedSocketCreation = 7000, StreamErrorTimedOut };

extern const unsigned int kStreamChunkSize;

enum { CONNECT = 0, COMMAND, ABORT, DISCONNECT, FORCE_DISCONNECT, CHECK_FILE_QUEUE, KILL_THREAD };		// port messages


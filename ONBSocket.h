// This code derives from Aaron Jacobs's OneButton Socket, which was
// at the time of writing normally licensed under the terms of the
// GNU General Public License.  You can find the "standard" version
// in the CVS repository of OneButton FTP (www.onebutton.org).
//
// The SPECIFIC INCARNATION of OneButton Socket upon which this
// code is based was specially distributed to Greg Hulands on 2006-01-05
// under the terms of a modified BSD-style license rather than the GPL.
// This does not indicate that any other version of OneButton Socket
// is or will be distributed under any license but the GPL.

/*
 * Copyright (c) 2005, Aaron Jacobs.
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above two paragraph
 *       note about licensing of OneButton Socket, the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Aaron Jacobs nor the names of OneButton Socket or
 *       OneButton FTP may be used to endorse or promote products derived from
 *       this software without specific prior written permission from Aaron Jacobs.
 *
 * THIS SOFTWARE IS PROVIDED BY AARON JACOBS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL AARON JACOBS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 * WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

/* 
	Modifications made by Greg Hulands to gel with the Connection Framework
*/

/*
	Thanks to Dustin Voss and his public domain AsyncSocket class for both
	the inspiration for this class and its method of listening for connections and
	handling communication with a delegate.
*/

#import <Cocoa/Cocoa.h>
#import "AbstractConnectionProtocol.h"

#define ONBSocketErrorDomain		@"ONBSocketErrorDomain"
#define ONBSocketSSLErrorDomain		@"ONBSocketSSLErrorDomain"

typedef enum
{
	ONBUnhandledStreamEvent,
	ONBConnectionClosed
} ONBSocketErrorCodes;

@class ONBSocket;
@class ONBSSLContext;
@class ONBSSLIdentity;

/*****************************************************************************************
	Delegate Methods (All Optional)
*****************************************************************************************/
@interface NSObject ( ONBSocketDelegate )

// The socket successfully connected to the host provided to connectToHost:port:.
- (void)socketDidConnect:(ONBSocket *)socket;

// A socket previously told to listen for connections is now listening on the
// given port.
- (void)socket:(ONBSocket *)socket
	acceptingConnectionsOnPort:(UInt16)port;

// An accepting socket spun off a new socket for an accepted connection.  newSocket
// is autoreleased, so remember to retain it.  newSocket will call
// socket:didConnectToHist:port: once it has successfull set up the connection.
- (void)socket:(ONBSocket *)socket
	didAcceptNewSocket:(ONBSocket *)newSocket;

// A read that was started with readDataOfLength:timeout:userInfo: succeeded.
- (void)socket:(ONBSocket *)socket
	didReadData:(NSData *)data
	userInfo:(NSDictionary *)userInfo;

// A read that was started with readDataOfLength:timeout:userInfo: timed out.
- (void)socket:(ONBSocket *)socket
	didTimeOutForReadWithUserInfo:(NSDictionary *)userInfo;

// A write that was started with writeData:timeout:userInfo: succeeded.
- (void)socket:(ONBSocket *)socket
	didWriteDataWithUserInfo:(NSDictionary *)userInfo;

// A write that was started with writeData:timeout:userInfo: timed out.
- (void)socket:(ONBSocket *)socket
	didTimeOutForWriteWithUserInfo:(NSDictionary *)userInfo;

//  The handshake initiated by enableSSL succeeded.
- (void)socketSSLHandshakeSucceeded:(ONBSocket *)socket;

// The handshake initiated by enableSSL failed.
- (void)socket:(ONBSocket *)socket
	sslHandshakeFailedWithError:(NSError *)error;

// The socket disconnected in some error state.  remainingData contains any data that
// came in over the socket before it disconnected but had not yet been used to fill a
// read request.  After this delegate method is called, the socket is useless and
// should be released.
- (void)socket:(ONBSocket *)socket
	didDisconnectWithError:(NSError *)error
	remainingData:(NSData *)remainingData;

@end

@interface ONBSocket : NSObject <InputStream, OutputStream>
{
	NSString				*_host;
	UInt16					_port;
	
	NSThread				*ONB_mainThread;
	NSThread				*ONB_socketThread;
	
	// Have we already told the socket thread to shut down once?
	BOOL					ONB_toldSocketThreadToShutDown;
	
	// SSL parameters which will be given to the SSL context when
	// it is first used.
	BOOL					ONB_verifySSLCertificates;
	BOOL					ONB_SSLServerMode;
	
	// The SSL identity used for encrypted communications.  This
	// class is effectively immutable, so sharing it should not
	// be a problem.
	ONBSSLIdentity			*ONB_SSLIdentity;

	/***************************************************************
		Main Thread Exclusive Instance Variables
	***************************************************************/

	id						ONB_delegate;
	
	// For storing invocations to later be sent to the socket thread.
	NSMutableArray			*ONB_socketThreadInvocations;
	
	double					ONB_transferSpeed;
	double					ONB_receiveSpeed;
	
	// The address from which we are communicating.
	NSString				*ONB_localHost;
	
	/***************************************************************
		Socket Thread Exclusive Instance Variables
	***************************************************************/

	// For storing invocations to later be sent to the main thread.
	NSMutableArray			*ONB_mainThreadInvocations;

	// Streams for reading and writing raw data
	NSInputStream			*ONB_inputStream;
	NSOutputStream			*ONB_outputStream;
	
	// The data straight from the input socket, without any SSL decoding.
	// Data only goes here when SSL is enabled.
	NSMutableData			*ONB_rawReadData;
	
	// Data read from the input socket and then decrypted is put here.
	// It is also put here if SSL is disabled.
	NSMutableData			*ONB_decryptedReadData;
	
	// Data that has been encrypted (or raw data if SSL is not enabled)
	// and is waiting to be consumed by the output stream
	NSMutableData			*ONB_encryptedWriteData;
	
	// Arrays to hold dictionaries that describe read and write requests.
	NSMutableArray			*ONB_readRequests;
	NSMutableArray			*ONB_writeRequests;
	
	// The next available read/write tag.  These are to keep track of
	// which timeout timers are old and which are current.
	unsigned int			ONB_availableReadTag;
	unsigned int			ONB_availableWriteTag;
	
	// Are we currently waiting for an SSL handshake to complete?
	BOOL					ONB_handshaking;
	
	// Has SSL successfully been set up?
	BOOL					ONB_sslEnabled;
	
	// How many stream open events have completed?  We have to wait for
	// both the input and the output stream to open before doing anything.
	unsigned int			ONB_streamOpenCount;
	
	// The object used to encrypt and decrypt data
	ONBSSLContext			*ONB_sslContext;
	
	// The CFSocket responsible for accepting new connections and associated objects
	CFSocketRef				ONB_acceptSocket;
	CFRunLoopSourceRef		ONB_runLoopSource;

	// For keeping track of read speed.
	struct timeval			ONB_lastReadSpeedReport;
	unsigned int			ONB_bytesReadSinceLastReadSpeedReport;
	
	// For keeping track of write speed.
	struct timeval			ONB_lastWriteSpeedReport;
	unsigned int			ONB_bytesWrittenSinceLastWriteSpeedReport;
	
	// For knowing when to exit the socket thread.
	BOOL					ONB_stopRunLoop;
}

/*****************************************************************************************
	Starting Up
*****************************************************************************************/

// Designated initializer
- (id)initWithDelegate:(id)delegate;

// The delegate is a weak reference.  Be sure to change it if the delegate gets released.
// Note that if you change the delegate while read and write requests are pending, the
// new delegate may receive completion notices for requests that the old delegate started.
- (id)delegate;
- (void)setDelegate:(id)delegate;

// Attempt to connect to the given host on the given port. The delegate method
// socket:didConnectToHost:port: will be called on success, and
// socket:didDisconnectWithError: in the event of a failure.
// Don't try to read or write any data until successfully connected.
- (void)connectToHost:(NSString *)host port:(UInt16)port;

- (void)setHost:(NSString *)host port:(UInt16)port;

// Listen to the given port and spin off new sockets for accepted connections.
// socket:didAcceptNewSocket: will be called on success, and
// socket:didDisconnectWithError: in the event of a failure.
// Give port 0 to choose a random high port.
// Don't try to read or write any data until successfully connected.
- (void)acceptConnectionsOnPort:(UInt16)port;


/*****************************************************************************************
	Status
*****************************************************************************************/

- (double)transferSpeed;
- (double)receiveSpeed;

// The host from which we are communicating, in a.b.c.d format.
- (NSString *)localHost;

/*****************************************************************************************
	SSL Support
*****************************************************************************************/

// Should certificates be verified against known root certificates?  Turn this off if
// you have self-signed or unsigned certificates.  The default is YES.  Note that
// not verifying certificates removes a significant layer of security from SSL.
- (BOOL)verifySSLCertificates;
- (void)setVerifySSLCertificates:(BOOL)verifySSLCertificates;

// The SSL identity that should be used in the SSL session.  This is required for
// SSL server mode.  Note that at this time it seems as if only RSA certificates work.
// DO NOT CALL setSSLIdentity AFTER YOU HAVE CALLED enableSSL!
- (ONBSSLIdentity *)sslIdentity;
- (void)setSSLIdentity:(ONBSSLIdentity *)sslIdentity;

// Should the socket operate in SSL server mode or client mode?  The default is client
// mode (NO).  If you change this to YES, you must also call setSSLCertificates:.
- (BOOL)sslServerMode;
- (void)setSSLServerMode:(BOOL)sslServerMode;


// Turn SSL support on, performing a handshake as soon as any pending write
// requests complete.  Do not call this until the socket has successfully connected and
// you have set up any SSL options above. Also, do not call this until you are sure
// you have read all of the unencrypted data that the other party has sent, otherwise
// unencrypted data may be interpreted as SSL handshake data.  If the handshake fails, 
// socket:sslHandshakeFailedWithError: will be called.  Otherwise,
// socketSSLHandshakeSucceeded: will be called.

// If the handshake fails, any data write requests sent after enableSSL is called will
// be transferred in the clear.  If it succeeds, they will be encrypted.  So if you
// are sending sensitive information, it is probably best to wait until the delegate
// method socketSSLHandshakeSucceeded: is called to make the write request.
- (void)enableSSL;


/*****************************************************************************************
	Reading
*****************************************************************************************/

// Request that a specific amount of data be read and given to the delegate, timing out if
// it takes too long.  If timeout is negative, the read will never time out. userInfo can
// be anything you need to keep track of (or nil).  It will be retained and then released
// when the read fails or succeeds and is reported to the user.
- (void)readDataOfLength:(unsigned int)length
					timeout:(NSTimeInterval)timeout
					userInfo:(NSDictionary *)userInfo;

// Request that the socket read data until it hits the first instance of the given
// terminator, and then give the data read (including the terminator) to the delegate.
// If timeout is non-negative, the read will time out if it takes longer than timeout
// seconds.  If it is negative, it will never time out.  userInfo can be anything you
// need to keep track of (or nil).  It will be retained and then released when the
// read fials or succeeds and is reported to the user.
- (void)readUntilData:(NSData *)terminator
				timeout:(NSTimeInterval)timeout
				userInfo:(NSDictionary *)userInfo;

// Use this method to retrieve any available data.  It will be put into the queue of read
// requests just like the other style of reading, and when any previous read requests have
// finished it will return any received data that is left or an empty NSData instance if
// there is none.
- (void)readAllAvailableDataWithTimeout:(NSTimeInterval)timeout
								userInfo:(NSDictionary *)userInfo;


/*****************************************************************************************
	Writing
*****************************************************************************************/

// Request that the given data be written to the socket and the success or failure of
// the operation be reported to the delegate.  The write will time out if it takes too long.
// If timeout is negative, the write will never time out.  userInfo can be anything you need
// to keep track of (or nil).  It will be retained and then released when the write fails or
// succeeds and is reported to the user.
- (void)writeData:(NSData *)data
			timeout:(NSTimeInterval)timeout
			userInfo:(NSDictionary *)userInfo;

@end
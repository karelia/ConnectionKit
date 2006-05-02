/*
 Copyright (c) 2005, Greg Hulands <ghulands@framedphotographics.com>
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

/*
 *	A Stream Based Connection runs the streams in a background thread and handles the
 *	delegate notifications of the streams.
 *
 *	Properties used:
 *		FileCheckingTranscript
 *
 */

@class RunLoopForwarder;

@interface StreamBasedConnection : AbstractQueueConnection 
{
	NSPort				*_port;
	RunLoopForwarder	*_forwarder;
	NSThread			*_bgThread;
	NSThread			*_createdThread;
	
	id<OutputStream>	_sendStream;
	id<InputStream>		_receiveStream;
	
	NSMutableData		*_sendBuffer;
	NSLock				*_sendBufferLock;
	
	// This is a peer connection that is used to check if files exist
	AbstractConnection	*_fileCheckingConnection;
	NSString			*_fileCheckInFlight;
	
	BOOL				_runThread;
}

- (void)openStreamsToPort:(unsigned)port;
- (void)scheduleStreamsOnRunLoop;

- (void)setSendStream:(NSStream *)stream;
- (void)setReceiveStream:(NSStream *)stream;
- (NSStream *)sendStream;
- (NSStream *)receiveStream;
- (void)closeStreams;

- (void)handleSendStreamEvent:(NSStreamEvent)theEvent;
- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent;
- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length;
- (void)stream:(id<InputStream>)stream readBytesOfLength:(unsigned)length;

// Get the local command port
- (unsigned)localPort;

- (void)sendPortMessage:(int)message;
- (void)handlePortMessage:(NSPortMessage *)message;

// Subclass needs to override these methods
- (void)processReceivedData:(NSData *)data;
- (void)sendCommand:(id)command;

- (void)sendData:(NSData *)data;
- (NSData *)availableData;

@end

extern NSString *StreamBasedErrorDomain;

enum { StreamErrorFailedSocketCreation = 7000 };

extern const unsigned int kStreamChunkSize;

enum { CONNECT = 0, COMMAND, ABORT, DISCONNECT, FORCE_DISCONNECT, CHECK_FILE_QUEUE, KILL_THREAD };		// port messages


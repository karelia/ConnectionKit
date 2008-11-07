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

#import <Cocoa/Cocoa.h>
#import <Security/SecureTransport.h>

@class ONBSSLIdentity;

@interface ONBSSLContext : NSObject
{
	SSLContextRef		ONB_sslContext;
	
	NSMutableData		*ONB_inputData;
	NSMutableData		*ONB_outputData;
	
	BOOL				ONB_verifySSLCerts;
	ONBSSLIdentity		*ONB_sslIdentity;
	BOOL				ONB_sslServerMode;
}

// Should certificates be verified against known root certificates?  Turn this off if
// you have self-signed or unsigned certificates.  The default is YES.  Note that
// not verifying certificates removes a significant layer of security from SSL.
// Must be set before starting a handshake.
- (BOOL)verifySSLCertificates;
- (void)setVerifySSLCertificates:(BOOL)verifySSLCertificates;

// The SSL identity that should be used in the SSL session.  This is required for
// SSL server mode.  Note that at this time it seems as if only RSA certificates work.
// Must be set before starting a handshake.
- (ONBSSLIdentity *)sslIdentity;
- (void)setSSLIdentity:(ONBSSLIdentity *)sslIdentity;

// Should the socket operate in SSL server mode or client mode?  The default is client
// mode (NO).  If you change this to YES, you must also call setSSLCertificates:.
// Must be set before starting a handshake.
- (BOOL)sslServerMode;
- (void)setSSLServerMode:(BOOL)sslServerMode;

// Perform a handshake.  inputData should be filled with data read from the socket
// and outputData should be empty.  When the method is done, inputData will contain
// any unused data and outputData will contain any data that needs to be written to
// the socket.  Returns 0 if it needs to be called back when more input data arrives
// and 1 if the handshake has completed.  Returns a negative error code on error.
- (int)handshakeWithInputData:(NSMutableData *)inputData
					outputData:(NSMutableData *)outputData;

// Encrypt data to be written to the socket.  Data will be taken from inputData (which
// should contain raw bytes from the socket) if any needs to be read in the process of
// the encryption.
- (NSData *)encryptData:(NSData *)data inputData:(NSMutableData *)inputData;

// Decrypt data read from the socket.  If not all of the data could be decrypted at
// the moment, the unused data will be left in the data object.  Data will be added
// to outputData if any needs to be written in the process of the decryption.
- (NSData *)decryptData:(NSMutableData *)data outputData:(NSMutableData *)outputData;

@end
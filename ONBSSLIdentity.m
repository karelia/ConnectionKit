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

#import "ONBSSLIdentity.h"

@implementation ONBSSLIdentity

- (id)init
{
	return [self initWithIdentityRef:nil];
}

- (id)initWithIdentityRef:(SecIdentityRef)identityRef
{
	if (! (self = [super init]))
		return nil;

	ONB_identity = identityRef;
	CFRetain(ONB_identity);
	
	return self;
}

- (void)dealloc
{
	CFRelease(ONB_identity);
	[super dealloc];
}

+ (ONBSSLIdentity *)defaultSSLIdentity
{
	return [self defaultSSLIdentityInKeychain:nil];
}

+ (ONBSSLIdentity *)defaultSSLIdentityInKeychain:(NSString *)keychainName
{
	SecKeychainRef keychainRef = nil;
	
	// If no keychain name was specified, use the default keychain.
	if (keychainName)
	{
		NSString *keychainsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains"];
		NSString *fullPath = [keychainsDirectory stringByAppendingPathComponent:keychainName];
		
		if (SecKeychainOpen([fullPath UTF8String], &keychainRef))
		{
			NSLog(@"Unable to open keychain");
			return nil;
		}
	}
	
	else if (SecKeychainCopyDefault(&keychainRef))
	{
			NSLog(@"Unable to get default keychain");
			return nil;
	}
	
	SecIdentitySearchRef searchRef = nil;
	if (SecIdentitySearchCreate(keychainRef, CSSM_KEYUSE_SIGN, &searchRef))
	{
		NSLog(@"Unable to create keychain search");
		CFRelease(keychainRef);
		return nil;
	}
	
	SecIdentityRef identityRef = nil;
	if (SecIdentitySearchCopyNext(searchRef, &identityRef))
	{
		NSLog(@"Unable to get next search result");
		CFRelease(keychainRef);
		CFRelease(searchRef);
		return nil;
	}
	
	ONBSSLIdentity *sslIdentity = [[[ONBSSLIdentity alloc] initWithIdentityRef:identityRef] autorelease];
	
	CFRelease(keychainRef);
	CFRelease(searchRef);
	CFRelease(identityRef);
	
	return sslIdentity;
}

- (SecIdentityRef)identityRef
{
	return ONB_identity;
}

@end
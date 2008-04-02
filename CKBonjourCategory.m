/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
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

#import "CKBonjourCategory.h"
#import "CKHost.h"
#import "AbstractConnection.h"
#import "ConnectionRegistry.h"

@interface CKBonjourHost : CKHost
{
	
}
@end

@implementation CKBonjourCategory

- (id)init
{
	if ((self = [super initWithName:@"Bonjour"]))
	{
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		NSNumber *use;
		
		use = [ud objectForKey:@"CKBonjourBrowsesFTP"];
		
		if (!use || [use boolValue])
		{
			myFTPCategory = [[CKHostCategory alloc] initWithName:@"FTP"];
			[myFTPCategory setEditable:NO];
			[super addChildCategory:myFTPCategory];
			myFTPBrowser = [[NSNetServiceBrowser alloc] init];
			[myFTPBrowser setDelegate:self];
			[myFTPBrowser searchForServicesOfType:@"_ftp._tcp." inDomain:@""];
		}
		
		use = [ud objectForKey:@"CKBonjourBrowsesSFTP"];
		
		if (!use || [use boolValue])
		{
			mySFTPCategory = [[CKHostCategory alloc] initWithName:@"SFTP"];
			[mySFTPCategory setEditable:NO];
			[super addChildCategory:mySFTPCategory];
			mySFTPBrowser = [[NSNetServiceBrowser alloc] init];
			[mySFTPBrowser setDelegate:self];
			[mySFTPBrowser searchForServicesOfType:@"_sftp-ssh._tcp." inDomain:@""];
		}
		
		use = [ud objectForKey:@"CKBonjourBrowsesWebDAV"];
		
		if (!use || [use boolValue])
		{
			myHTTPCategory = [[CKHostCategory alloc] initWithName:@"WebDAV"];
			[myHTTPCategory setEditable:NO];
			[super addChildCategory:myHTTPCategory];
			myHTTPBrowser = [[NSNetServiceBrowser alloc] init];
			[myHTTPBrowser setDelegate:self];
			[myHTTPBrowser searchForServicesOfType:@"_http._tcp." inDomain:@""];
		}
	}
	return self;
}

- (void)dealloc
{
	[myFTPBrowser stop];
	[myFTPBrowser release];
	[mySFTPBrowser stop];
	[mySFTPBrowser release];
	[myHTTPBrowser stop];
	[myHTTPBrowser release];
	
	[myFTPCategory release];
	[mySFTPCategory release];
	[myHTTPCategory release];
	
	[super dealloc];
}

static NSImage *sBonjourIcon = nil;

- (NSImage *)icon
{
	if (!sBonjourIcon)
	{
		NSBundle *b = [NSBundle bundleForClass:[self class]];
		NSString *p = [b pathForResource:@"bonjour" ofType:@"png"];
		sBonjourIcon = [[NSImage alloc] initWithContentsOfFile:p];
	}
	return sBonjourIcon;
}

- (void)addChildCategory:(CKHostCategory *)cat
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:LocalizedStringInConnectionKitBundle(@"You can not add a child collection to the Bonjour category.",@"Bonjour Error")
								 userInfo:nil];
}

- (void)addHost:(CKHost *)host
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:LocalizedStringInConnectionKitBundle(@"You can not add a new server to the Bonjour category.",@"Bonjour Error")
								 userInfo:nil];
}

- (BOOL)isEditable
{
	return NO;
}

#pragma mark -
#pragma mark Browser Delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
	[netService setDelegate:self];
	[netService resolveWithTimeout:10];
	[netService retain];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
	NSMutableArray *allBonjourHosts = [NSMutableArray array];
	[allBonjourHosts addObjectsFromArray:[myFTPCategory hosts]];
	[allBonjourHosts addObjectsFromArray:[mySFTPCategory hosts]];
	[allBonjourHosts addObjectsFromArray:[myHTTPCategory hosts]];
	
	NSEnumerator *e = [allBonjourHosts objectEnumerator];
	CKHost *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur userInfo] == netService)
		{
			[[cur category] removeHost:cur];
			break;
		}
	}
	
	if (!moreServicesComing)
	{
		[[[ConnectionRegistry sharedRegistry] outlineView] reloadData];
	}
}

#pragma mark -
#pragma mark Net Service Delegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	CKBonjourHost *h = [[CKBonjourHost alloc] init];
	[h setHost:[sender hostName]];
	[h setUserInfo:sender];
	[h setAnnotation:[sender name]];
	[sender release];
	[h setUsername:NSUserName()];
	
	if ([[sender type] isEqualToString:@"_ftp._tcp."])
	{
		[h setConnectionType:@"FTP"];
		[myFTPCategory addHost:h];
	}
	else if (([[sender type] isEqualToString:@"_sftp-ssh._tcp."]))
	{
		[h setConnectionType:@"SFTP"];
		[mySFTPCategory addHost:h];
	}
	else if (([[sender type] isEqualToString:@"_http._tcp."]))
	{
		[h setConnectionType:@"WebDAV"];
		[myHTTPCategory addHost:h];
	}
	[h setPort:[AbstractConnection registeredPortForConnectionType:[h connectionType]]];
	[h release];
	[[[ConnectionRegistry sharedRegistry] outlineView] reloadData];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
	NSLog(@"%@", errorDict);
}

@end

@implementation CKBonjourHost

- (BOOL)isEditable
{
	return NO;
}

@end

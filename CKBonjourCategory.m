//
//  CKBonjourCategory.m
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKBonjourCategory.h"
#import "CKHost.h"
#import "AbstractConnection.h"

@interface CKBonjourHost : CKHost
{
	
}
@end

@implementation CKBonjourCategory

- (id)init
{
	if ((self = [super initWithName:@"Bonjour"]))
	{
		myFTPCategory = [[CKHostCategory alloc] initWithName:@"ftp"];
		mySFTPCategory = [[CKHostCategory alloc] initWithName:@"sftp"];
		myHTTPCategory = [[CKHostCategory alloc] initWithName:@"webdav"];
		
		[super addChildCategory:myFTPCategory];
		[super addChildCategory:mySFTPCategory];
		[super addChildCategory:myHTTPCategory];
		
		myFTPBrowser = [[NSNetServiceBrowser alloc] init];
		[myFTPBrowser setDelegate:self];
		[myFTPBrowser searchForServicesOfType:@"_ftp._tcp." inDomain:@""];
		mySFTPBrowser = [[NSNetServiceBrowser alloc] init];
		[mySFTPBrowser setDelegate:self];
		[mySFTPBrowser searchForServicesOfType:@"_sftp-ssh._tcp." inDomain:@""];
		myHTTPBrowser = [[NSNetServiceBrowser alloc] init];
		[myHTTPBrowser setDelegate:self];
		[myHTTPBrowser searchForServicesOfType:@"_http._tcp." inDomain:@""];
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
								   reason:LocalizedStringInThisBundle(@"You can not add a child category to the Bonjour category.",@"Bonjour Error")
								 userInfo:nil];
}

- (void)addHost:(CKHost *)host
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:LocalizedStringInThisBundle(@"You can not add a new host to the Bonjour category.",@"Bonjour Error")
								 userInfo:nil];
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
	NSEnumerator *e = [[myFTPCategory hosts] objectEnumerator];
	CKHost *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur userInfo] == netService)
		{
			[myFTPCategory removeHost:cur];
			return;
		}
	}
	e = [[mySFTPCategory hosts] objectEnumerator];
	while ((cur = [e nextObject]))
	{
		if ([cur userInfo] == netService)
		{
			[mySFTPCategory removeHost:cur];
			return;
		}
	}
	e = [[myHTTPCategory hosts] objectEnumerator];
	while ((cur = [e nextObject]))
	{
		if ([cur userInfo] == netService)
		{
			[myHTTPCategory removeHost:cur];
			return;
		}
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
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
	NSLog(@"%@", errorDict);
}

@end

@implementation CKBonjourHost

- (CKHostCategory *)category
{
	return nil;
}

@end

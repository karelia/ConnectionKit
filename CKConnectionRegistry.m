//
//  CKConnectionRegistry.m
//  Connection
//
//  Created by Mike on 05/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import "CKConnectionRegistry.h"

#import "CKAbstractConnection.h"

#import "NSURL+Connection.h"


@implementation CKConnectionRegistry

+ (CKConnectionRegistry *)sharedConnectionRegistry
{
    static CKConnectionRegistry *result;
    if (!result)
    {
        result = [[CKConnectionRegistry alloc] init];
    }
    
    return result;
}

- (id)init
{
    if (self = [super init])
    {
        _connectionClassesByName = [[NSMutableDictionary alloc] init];
        _connectionClassesByURLScheme = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_connectionClassesByURLScheme release];
    [_connectionClassesByName release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Class Registration

- (void)registerClass:(Class <CKConnection>)connectionClass forName:(NSString *)name URLScheme:(NSString *)URLScheme
{
    [_connectionClassesByName setObject:connectionClass forKey:name];
    
    if (URLScheme)
    {
        [_connectionClassesByURLScheme setObject:connectionClass forKey:URLScheme];
    }
}

- (Class <CKConnection>)connectionClassForURLScheme:(NSString *)URLScheme
{
    return [_connectionClassesByURLScheme objectForKey:URLScheme];
}

- (Class <CKConnection>)connectionClassForName:(NSString *)connectionName
{
    return [_connectionClassesByName objectForKey:connectionName];
}

- (NSURLRequest *)connectionRequestForName:(NSString *)name host:(NSString *)host port:(NSNumber *)port
{
    Class connectionClass = [self connectionClassForName:name];
    
    NSURL *URL = [[NSURL alloc] initWithScheme:[[connectionClass URLSchemes] objectAtIndex:0]
                                          host:host
                                          port:port
                                          user:nil
                                      password:nil];
    
    NSURLRequest *result = [NSURLRequest requestWithURL:URL];
    [URL release];
    return result;
}

#pragma mark -
#pragma mark Connection Creation

- (id <CKConnection>)connectionWithRequest:(NSURLRequest *)request
{
    Class class = [self connectionClassForURLScheme:[[request URL] scheme]];
    
    id <CKConnection> result = nil;
    if (class)
    {
        result = [[[class alloc] initWithRequest:request] autorelease];
    }
    
    return result;
}

- (id <CKConnection>)connectionWithName:(NSString *)name host:(NSString *)host port:(NSNumber *)port
{
    return [self connectionWithName:name host:host port:port user:nil password:nil error:NULL];
}

- (id <CKConnection>)connectionWithName:(NSString *)name host:(NSString *)host port:(NSNumber *)port user:(NSString *)username password:(NSString *)password error:(NSError **)error
{
    Class class = [self connectionClassForName:name];
    
    id <CKConnection> result = nil;
    if (class)
    {
        NSURL *URL = [[NSURL alloc] initWithScheme:[[class URLSchemes] objectAtIndex:0]
                                              host:host
                                              port:port
                                              user:username
                                          password:password];
        
        result = [[[class alloc] initWithRequest:[NSURLRequest requestWithURL:URL]] autorelease];
        [URL release];
    }
                      
    if (!result && error)
	{
		NSError *err = [NSError errorWithDomain:CKConnectionErrorDomain
										   code:CKConnectionNoConnectionsAvailable
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(
																																@"No connection available for requested connection type", @"failed to find a connection class"),
												 NSLocalizedDescriptionKey,
												 [(*error) localizedDescription],
												 NSLocalizedRecoverySuggestionErrorKey,	// some additional context
												 nil]];
		*error = err;
	}
	
    return result;
}

#pragma mark URLs

- (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    NSString *scheme = [baseURL scheme];
    
    // FTP is special. Absolute paths need to specified with an extra prepended slash <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if ([scheme isEqualToString:@"ftp"] && [path isAbsolutePath])
    {
        // Get to host's URL, including single trailing slash
        // -absoluteURL has to be called so that the real path can be properly appended
        baseURL = [[NSURL URLWithString:@"/" relativeToURL:baseURL] absoluteURL];
        return [baseURL URLByAppendingPathComponent:path isDirectory:YES];
    }
    
    // SCP and SFTP represent the home directory using ~/ at the start of the path <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if (![path isAbsolutePath] &&
        ([scheme isEqualToString:@"scp"] || [scheme isEqualToString:@"sftp"]) &&
        [[baseURL path] length] <= 1)
    {
        path = [@"/~" stringByAppendingPathComponent:path];
    }
    
    return [NSURL URLWithString:path relativeToURL:baseURL];
}

- (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    NSString *scheme = [URL scheme];
    
    // FTP is special. The first slash of the path is to be ignored <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if ([scheme isEqualToString:@"ftp"])
    {
        CFStringRef strictPath = CFURLCopyStrictPath((CFURLRef)[URL absoluteURL], NULL);
        NSString *result = [(NSString *)strictPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (strictPath) CFRelease(strictPath);
        return result;
    }
    
    NSString *result = [URL path];
    
    // SCP and SFTP represent the home directory using ~/ at the start of the path
    if ([scheme isEqualToString:@"scp"] || [scheme isEqualToString:@"sftp"])
    {
        if ([result hasPrefix:@"/~/"]) result = [result substringFromIndex:3];
    }
    
    return result;
}

@end

//
//  CK2SFTPProtocol.m
//  Connection
//
//  Created by Mike on 15/10/2012.
//
//

#import "CK2SFTPProtocol.h"

@implementation CK2SFTPProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    return ([@"scp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"sftp" caseInsensitiveCompare:scheme] == NSOrderedSame);
}

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // SCP and SFTP represent the home directory using ~/ at the start of the path <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if (![path isAbsolutePath] && [[baseURL path] length] <= 1)
    {
        path = [@"/~" stringByAppendingPathComponent:path];
    }
    
    return [super URLWithPath:path relativeToURL:baseURL];
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    NSString *result = [super pathOfURLRelativeToHomeDirectory:URL];
    
    // SCP and SFTP represent the home directory using ~/ at the start of the path
    if ([result hasPrefix:@"/~/"])
    {
        result = [result substringFromIndex:3];
    }
    else if ([result isEqualToString:@"/~"])
    {
        result = @".";
    }
    
    return result;
}

@end

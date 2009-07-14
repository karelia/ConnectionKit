//
//  CKHTTPBasedProtocol.m
//  ConnectionKit
//
//  Created by Mike on 14/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKHTTPBasedProtocol.h"


@implementation CKHTTPBasedProtocol

- (void)downloadContentsOfFileAtPath:(NSString *)remotePath
{
    // Downloads are just simple GET requests
    NSURL *URL = [[NSURL alloc] initWithString:remotePath relativeToURL:[[self request] URL]];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    [URL release];
    
    
    // Start the request
    [self startOperationWithRequest:request];
    [request release];
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    // Send a PUT request with the data
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"PUT"];
    [URL release];
    
    
    // TODO:Include MIME type
    /*
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                            (CFStringRef)[path pathExtension],
                                                            NULL);
    NSString *MIMEType = [NSMakeCollectable(UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType)) autorelease];	
    if (!MIMEType || [MIMEType length] == 0)
    {
        // if this list grows, consider using a dictionary of corrected UTI to MIME mappings instead
        if ([(NSString *)UTI isEqualToString:@"public.css"])
        {
            MIMEType = @"text/css";
        }
        else if ([(NSString *)UTI isEqualToString:(NSString *)kUTTypeICO])
        {
            MIMEType = @"image/vnd.microsoft.icon";
        }
        else
        {
            MIMEType = @"application/octet-stream";
        }
    }
    CFRelease(UTI);
    
    [request setValue:MIMEType forHTTPHeaderField:@"Content-Type"];
    */
    
    // Include data -- does this automatically include a content-length header?
    [request setHTTPBody:data];
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

- (void)deleteItemAtPath:(NSString *)path
{
    // Send a DELETE request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"DELETE"];
    [URL release];
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

@end

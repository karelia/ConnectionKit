//
//  CK2FileProtocol.m
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2FileProtocol.h"

@implementation CK2FileProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url isFileURL];
}

+ (CK2FileTransferProtocol *)startEnumeratingContentsOfURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2FileTransferProtocolClient>)client;
{
    NSFileManager *manager = [[NSFileManager alloc] init];
    
    // Enumerate contents
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:url includingPropertiesForKeys:keys options:mask errorHandler:^BOOL(NSURL *url, NSError *error) {
        
        NSLog(@"enumeration error: %@", error);
        return YES;
    }];
    
    CK2FileProtocol *protocol = [[self alloc] init];
    
    BOOL reportedDirectory = NO;
    
    NSURL *aURL;
    while (aURL = [enumerator nextObject])
    {
        // Report the main directory first
        if (!reportedDirectory)
        {
            [client fileTransferProtocol:protocol didDiscoverItemAtURL:url];
            reportedDirectory = YES;
        }
        
        [client fileTransferProtocol:protocol didDiscoverItemAtURL:aURL];
    }
    
    [manager release];
    
    [client fileTransferProtocolDidFinish:protocol];
    return [protocol autorelease];
}

+ (CK2FileTransferProtocol *)startCreatingDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client;
{
    NSFileManager *manager = [[NSFileManager alloc] init];
    CK2FileProtocol *protocol = [[self alloc] init];
    
    NSError *error;
    if ([manager createDirectoryAtURL:url withIntermediateDirectories:createIntermediates attributes:nil error:&error])
    {
        [client fileTransferProtocolDidFinish:protocol];
    }
    else
    {
        [client fileTransferProtocol:protocol didFailWithError:error];
    }
    
    [manager release];
    return [protocol autorelease];
}

+ (CK2FileTransferProtocol *)startCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    CK2FileProtocol *protocol = [[self alloc] init];

    NSData *data = [request HTTPBody];
    if (data)
    {
        // TODO: Use a stream or similar to write incrementally and report progress
        NSError *error;
        if ([data writeToURL:[request URL] options:0 error:&error])
        {
            [client fileTransferProtocolDidFinish:protocol];
        }
        else
        {
            [client fileTransferProtocol:protocol didFailWithError:error];
        }
    }
    else
    {
        // TODO: Work asynchronously so aren't blocking this one throughout the write
        NSInputStream *inputStream = [request HTTPBodyStream];
        [inputStream open];
        
        NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:[request URL] append:NO];
        [outputStream open];
        // TODO: Handle outputStream being nil?
        
        uint8_t buffer[1024];
        while ([inputStream hasBytesAvailable])
        {
            NSUInteger length = [inputStream read:buffer maxLength:1024];
            
            // FIXME: Handle not all the bytes being written
            [outputStream write:buffer maxLength:length];
            
            // FIXME: Report any error reading or writing
            
            progressBlock(length);
        }
        
        [inputStream close];
        [outputStream close];
        [outputStream release];
        
        [client fileTransferProtocolDidFinish:protocol];
    }
    
    return [protocol autorelease];
}

+ (CK2FileTransferProtocol *)startRemovingFileAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client;
{
    NSFileManager *manager = [[NSFileManager alloc] init];
    CK2FileProtocol *protocol = [[self alloc] init];
    
    NSError *error;
    if ([manager removeItemAtURL:url error:&error])
    {
        [client fileTransferProtocolDidFinish:protocol];
    }
    else
    {
        [client fileTransferProtocol:protocol didFailWithError:error];
    }
    
    [manager release];
    return [protocol autorelease];
}

+ (CK2FileTransferProtocol *)startSettingResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client;
{
    CK2FileProtocol *protocol = [[self alloc] init];

    NSError *error;
    if ([url setResourceValues:keyedValues error:&error])
    {
        [client fileTransferProtocolDidFinish:protocol];
    }
    else
    {
        [client fileTransferProtocol:protocol didFailWithError:error];
    }
    
    return [protocol autorelease];
}

@end

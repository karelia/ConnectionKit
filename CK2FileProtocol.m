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

- (id)initWithBlock:(void (^)(void))block;
{
    if (self = [self init])
    {
        _block = [_block copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_block release];
    [super dealloc];
}

- (id)initForEnumeratingDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2FileTransferProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        // Enumerate contents
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:url includingPropertiesForKeys:keys options:mask errorHandler:^BOOL(NSURL *url, NSError *error) {
            
            NSLog(@"enumeration error: %@", error);
            return YES;
        }];
                
        BOOL reportedDirectory = NO;
        
        NSURL *aURL;
        while (aURL = [enumerator nextObject])
        {
            // Report the main directory first
            if (!reportedDirectory)
            {
                [client fileTransferProtocol:self didDiscoverItemAtURL:url];
                reportedDirectory = YES;
            }
            
            [client fileTransferProtocol:self didDiscoverItemAtURL:aURL];
        }
                
        [client fileTransferProtocolDidFinish:self];
    }];
}

- (id)initForCreatingDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:createIntermediates attributes:nil error:&error])
        {
            [client fileTransferProtocolDidFinish:self];
        }
        else
        {
            [client fileTransferProtocol:self didFailWithError:error];
        }
    }];
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    return [self initWithBlock:^{
        
        NSData *data = [request HTTPBody];
        if (data)
        {
            // TODO: Use a stream or similar to write incrementally and report progress
            NSError *error;
            if ([data writeToURL:[request URL] options:0 error:&error])
            {
                [client fileTransferProtocolDidFinish:self];
            }
            else
            {
                [client fileTransferProtocol:self didFailWithError:error];
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
            
            [client fileTransferProtocolDidFinish:self];
        }
    }];
}

- (id)initForRemovingFileAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client
{
    return [self initWithBlock:^{
                
        NSError *error;
        if ([[NSFileManager defaultManager] removeItemAtURL:url error:&error])
        {
            [client fileTransferProtocolDidFinish:self];
        }
        else
        {
            [client fileTransferProtocol:self didFailWithError:error];
        }
    }];
}

- (id)initForSettingResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([url setResourceValues:keyedValues error:&error])
        {
            [client fileTransferProtocolDidFinish:self];
        }
        else
        {
            [client fileTransferProtocol:self didFailWithError:error];
        }
    }];
}

- (void)start;
{
    _block();
}

@end

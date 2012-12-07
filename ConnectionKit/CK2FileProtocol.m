//
//  CK2FileProtocol.m
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2FileProtocol.h"

#import "CK2CURLBasedProtocol.h"


@implementation CK2FileProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url isFileURL];
}

- (id)initWithBlock:(void (^)(void))block;
{
    if (self = [self init])
    {
        NSAssert(block != nil, @"should have a valid block");
        _block = [block copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_block release];
    [super dealloc];
}

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        // Enumerate contents
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[request URL]
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                               errorHandler:^BOOL(NSURL *url, NSError *error) {
            
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
                [client protocol:self didDiscoverItemAtURL:[request URL]];
                reportedDirectory = YES;
            }
            
            [client protocol:self didDiscoverItemAtURL:aURL];
        }
                
        [client protocolDidFinish:self];
    }];
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] createDirectoryAtURL:[request URL] withIntermediateDirectories:createIntermediates attributes:attributes error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    return [self initWithBlock:^{
        
        // Sadly libcurl doesn't support creating intermediate directories for local files, so do it ourself
        if (createIntermediates)
        {
            NSError *error;
            NSURL* intermediates = [[request URL] URLByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:intermediates withIntermediateDirectories:YES attributes:nil error:&error])
            {
                [client protocol:self didFailWithError:error];
                return;
            }
        }
        
        // Hand off to CURLHandle to create the file
        __block CK2CURLBasedProtocol *curlProtocol = [[CK2CURLBasedProtocol alloc] initWithRequest:request client:nil progressBlock:progressBlock completionHandler:^(NSError *error) {
            
            if (error)
            {
                [client protocol:self didFailWithError:error];
            }
            else
            {
                [client protocolDidFinish:self];
            }
            
            [curlProtocol autorelease];
        }];
        
        [curlProtocol start];
    }];
}

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
                
        NSError *error;
        if ([[NSFileManager defaultManager] removeItemAtURL:[request URL] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] setAttributes:keyedValues ofItemAtPath:[[request URL] path] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (void)start;
{
    _block();
}

@end

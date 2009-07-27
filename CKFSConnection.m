//
//  CKFSConnection.m
//  ConnectionKit
//
//  Created by Mike on 26/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFSConnection.h"

#import "CKFSItemInfo.h"


@implementation CKFSConnection

- (id)initWithProtocol:(id <CKReadOnlyFS>)filesystem;
{
    [self init];
    _protocol = filesystem;
    return self;
}

- (void)dealloc
{
    [_protocol release];
    [super dealloc];
}

- (BOOL)createDirectoryAtPath:(NSString *)remotePath
  withIntermediateDirectories:(BOOL)createIntermediates
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)outError
{
    NSParameterAssert(remotePath);
    NSParameterAssert([remotePath isAbsolutePath]);
    
    
    NSError *error = nil;
    BOOL result = [_protocol createDirectoryAtPath:remotePath
                                        attributes:attributes
                                             error:&error];
    
    if (createIntermediates &&
        !result &&
        [[error domain] isEqualToString:NSPOSIXErrorDomain] &&
        [error code] == ENOENT)
    {
        result = [self createDirectoryAtPath:[remotePath stringByDeletingLastPathComponent]
                 withIntermediateDirectories:YES
                                  attributes:attributes
                                       error:&error];
        
        if (result)
        {
            result = [self createDirectoryAtPath:remotePath
                     withIntermediateDirectories:NO
                                      attributes:attributes
                                           error:&error];
        }
    }
    
    if (!result && outError) *outError = error;
    return result;
}

- (BOOL)createFileAtPath:(NSString *)remotePath
                contents:(NSData *)contents
              attributes:(NSDictionary *)attributes
                   error:(NSError **)outError
{
    
}

- (NSData *)contentsOfFileAtPath:(NSString *)remotePath
                           error:(NSError **)outError
{
    NSData *result = nil;
    
    if (![_protocol respondsToSelector:@selector(contentsAtPath:)])
    {
        // Easy option, read it all in at once
        result = [_protocol contentsAtPath:remotePath];
        if (!result && outError)
        {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code:ENOENT
                                        userInfo:nil];
        }
    }
    else
    {
        // Open the file for reading
        id userData = nil;
        BOOL success = [_protocol openFileAtPath:remotePath
                                            mode:O_RDONLY
                                        userData:&userData
                                           error:outError];
        if (success)
        {
            // Read in all the chunks
            NSMutableData *resultBuffer = [[NSMutableData alloc] init];
            
            char buffer[4096];
            off_t offset = 0;
            
            while (success)
            {
                int bytesRead = [_protocol readFileAtPath:remotePath
                                                 userData:userData
                                                   buffer:buffer
                                                     size:4096
                                                   offset:offset
                                                    error:outError];
                
                if (bytesRead == 0)
                {
                    break;
                }
                else if (bytesRead > 0)
                {
                    [resultBuffer appendBytes:buffer length:bytesRead];
                    offset += bytesRead;
                }
                else
                {
                    success = NO;
                }
            }
            
            
            // Finish up the file
            [_protocol releaseFileAtPath:remotePath userData:userData];
            
            if (success)
            {
                result = [resultBuffer autorelease];
            }
            else
            {
                [resultBuffer release];
            }
        }
    }
    
    return result;
}

- (CKFSItemInfo *)contentsOfDirectoryAtPath:(NSString *)remotePath
                                      error:(NSError **)outError
{
    CKFSItemInfo *result = nil;
    
    if ([_protocol respondsToSelector:@selector(loadContentsOfDirectoryAtPath:error:)])
    {
        result = [_protocol loadContentsOfDirectoryAtPath:remotePath error:outError];
    }
    else
    {
        NSArray *contents = [_protocol contentsOfDirectoryAtPath:remotePath error:outError];
        if (contents)
        {
            result = [CKFSItemInfo infoWithFilenames:contents];
        }
    }
    
    return result;
}

@end

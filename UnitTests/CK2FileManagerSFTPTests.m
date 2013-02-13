//
//  CK2FileManagerSFTPTests.m
//  Connection
//
//  Created by Mike on 07/12/2012.
//
//

#import "CK2FileManagerBaseTests.h"
#import <SenTestingKit/SenTestingKit.h>


@interface CK2FileManagerSFTPTests : CK2FileManagerBaseTests

@end


@implementation CK2FileManagerSFTPTests

- (BOOL)setup
{
    BOOL result = ([self setupSessionWithResponses:@"sftp"]);
    return result;
}

- (void)testContentsOfHomeDirectory;
{
    if ([self setup])
    {
        NSURL *home = [self URLForPath:@""];
        
        [self.session contentsOfDirectoryAtURL:home includingPropertiesForKeys:nil options:0 completionHandler:^(NSArray *contents, NSError *error) {
            
            STAssertNotNil(contents, nil);
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateDirectory;
{
    if ([self setup])
    {
        NSURL *folder = [self URLForPath:@"CK2FileManagerSFTPTests"];
        
        [self.session createDirectoryAtURL:folder withIntermediateDirectories:NO openingAttributes:@{ NSFilePosixPermissions : @(0700) } completionHandler:^(NSError *error) {
            
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateFile;
{
    if ([self setup])
    {
        NSURL *file = [self URLForPath:@"CK2FileManagerSFTPTests/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        
        [self.session createFileAtURL:file contents:data withIntermediateDirectories:NO openingAttributes:@{ NSFilePosixPermissions : @(0600) } progressBlock:nil completionHandler:^(NSError *error) {
            
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testChangeAttributes;
{
    if ([self setup])
    {
        NSURL *folder = [self URLForPath:@"CK2FileManagerSFTPTests"];
        
        [self.session setAttributes:@{ NSFilePosixPermissions : @(0755) } ofItemAtURL:folder completionHandler:^(NSError *error) {
            
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

@end

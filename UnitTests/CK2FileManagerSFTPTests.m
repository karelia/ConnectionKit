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

- (void)testContentsOfHomeDirectory;
{
    if ([self setupSession])
    {
        NSURL *home = [CK2FileManager URLWithPath:@"" relativeToURL:[NSURL URLWithString:@"sftp://localhost/"]];
        
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
    if ([self setupSession])
    {
        NSURL *folder = [CK2FileManager URLWithPath:@"test" relativeToURL:[NSURL URLWithString:@"sftp://localhost/"]];
        
        [self.session createDirectoryAtURL:folder withIntermediateDirectories:NO openingAttributes:@{ NSFilePosixPermissions : @(0700) } completionHandler:^(NSError *error) {
            
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateFile;
{
    if ([self setupSession])
    {
        NSURL *file = [CK2FileManager URLWithPath:@"test.txt" relativeToURL:[NSURL URLWithString:@"sftp://localhost/"]];
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
    if ([self setupSession])
    {
        NSURL *folder = [CK2FileManager URLWithPath:@"test" relativeToURL:[NSURL URLWithString:@"sftp://localhost/"]];
        
        [self.session setAttributes:@{ NSFilePosixPermissions : @(0755) } ofItemAtURL:folder completionHandler:^(NSError *error) {
            
            STAssertNil(error, nil);
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

@end

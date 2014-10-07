//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

#import "KMSServer.h"
#import "KMSTranscriptEntry.h"

#import "CK2FileManagerWithTestSupport.h"

#import "CK2Authentication.h"

#import <XCTest/XCTest.h>
#import <curl/curl.h>

@implementation BaseCKProtocolTests


- (BOOL)setupTest
{
    BOOL result;
    if ([self isMemberOfClass:[BaseCKProtocolTests class]])
    {
        XCTFail(@"Are you trying to run the tests on BaseCKProtocolTests? They should be run by subclasses.");
        result = NO;
    }
    else
    {
        result = [super setupTest];
    }

    return result;
}

- (void)tearDown
{
    if ([self isSetup])
    {
        [self removeTestDirectory];
    }

    [super tearDown];
}

- (void)enumerateWithBadURLS:(void (^)(NSURL* url))block
{
    if ([self setupTest])
    {
        NSArray* badURLS = @[@"idontexist-noreally.com/nonexistantfolder", @"127.0.0.1/nonexistantfolder"];
        for (NSString* urlPart in badURLS)
        {
            NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", [self.protocol lowercaseString], urlPart]];
            block(url);
        }
    }
}



#pragma mark - Tests

- (void)testMakeRemoveOnly
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        [self removeTestDirectory];
    }
}

- (void)testContentsOfDirectoryAtURL
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        if (self.useMockServer)
        {
            self.server.data = [self mockServerDirectoryListingData];
        }

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            if (error)
            {
                XCTFail(@"got error %@", error);
            }
            else
            {
                NSUInteger count = [contents count];
                XCTAssertTrue(count == 2, @"should have two results, had %ld", count);
                if (count == 2)
                {
                    [self checkURL:contents[0] isNamed:[[self URLForTestFile1] lastPathComponent]];
                    [self checkURL:contents[1] isNamed:[[self URLForTestFile2] lastPathComponent]];
                }
            }

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testContentsOfDirectoryAtURLBadURL
{
    [self enumerateWithBadURLS:^(NSURL *url) {
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testContentsOfDirectoryAtURLBadLogin
{
    if ([self setupTest] && [self protocolUsesAuthentication])
    {
        [self useBadLogin];

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            XCTAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            XCTAssertTrue([contents count] == 0, @"shouldn't get content");

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testEnumerateContentsOfURL
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        if (self.useMockServer)
        {
            self.server.data = [self mockServerDirectoryListingData];
        }

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
        NSMutableArray* expectedURLS = [NSMutableArray arrayWithArray:@[
                                        url,
                                        [self URLForTestFile1],
                                        [self URLForTestFile2]
                                        ]];

        [self.manager enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            NSLog(@"got item %@", item);
            [self checkURLs:expectedURLS containItemNamed:[item lastPathComponent]];
        } completionHandler:^(NSError *error) {
            if (error)
            {
                XCTFail(@"got error %@", error);
            }
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testEnumerateContentsOfURLBadURL
{
    [self enumerateWithBadURLS:^(NSURL *url) {
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
        [self.manager enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
        } completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testEnumerateContentsOfURLBadLogin
{
    if ([self setupTest] && [self protocolUsesAuthentication])
    {
        [self useBadLogin];
        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
        [self.manager enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {

            XCTFail(@"shouldn't get any items");

        } completionHandler:^(NSError *error) {

            XCTAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            [self pause];

        }];

        [self runUntilPaused];
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setupTest])
    {
        [self removeTestDirectory];

        NSURL* url = [self URLForTestFolder];
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateDirectoryAtURLBadURL
{
    [self enumerateWithBadURLS:^(NSURL *url) {
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testCreateDirectoryAtURLAlreadyExists
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"make fails"];

        NSURL* url = [self URLForTestFolder];
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            BOOL errorCanBeNil = [self usingProtocol:@"file"]; // the file protocol doesn't report an error in this situation
            XCTAssertTrue([self checkIsCreationError:error nilAllowed:errorCanBeNil], @"expected file can't write error, got %@", error);

            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateDirectoryAtURLBadLogin
{
    if ([self setupTest] && [self protocolUsesAuthentication])
    {
        [self useBadLogin];
        NSURL* url = [self URLForTestFolder];
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {

            XCTAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@ underlying %@", error, error.userInfo[NSUnderlyingErrorKey]);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURL
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* url = [self URLForTestFile1];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURLBadURL
{
    NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
    [self enumerateWithBadURLS:^(NSURL *url) {
        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testCreateFileAtURL2
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* temp = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        NSURL* source = [temp URLByAppendingPathComponent:@"test.txt"];
        NSError* error = nil;
        XCTAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        NSURL* url = [self URLForTestFile1];

        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:source error:&error], @"failed to remove temporary file with error %@", error);
    }
}

- (void)testCreateFileAtURLBadURL2
{
    NSURL* temp = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL* source = [temp URLByAppendingPathComponent:@"test.txt"];
    NSError* error = nil;
    XCTAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

    [self enumerateWithBadURLS:^(NSURL *url) {
        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];

    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:source error:&error], @"failed to remove temporary file with error %@", error);
}

- (void)testCreateFileAtURLSourceDoesntExist
{
    if ([self setupTest])
    {
        NSURL* source = [NSURL fileURLWithPath:@"/tmp/i-dont-exist.txt"];
        NSURL* url = [self URLForTestFile1];

        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURLSourceIsntLocal
{
    if ([self setupTest])
    {
        NSURL* source = [NSURL URLWithString:@"http://karelia.com/tmp/i-dont-exist.txt"];
        NSURL* url = [self URLForTestFile1];

        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testUploadOver16k
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* url = [self URLForTestFile1];

        // make a block of data and fill it with stuff in an attempt to avoid any sneaky compression speeding things up
        NSUInteger length = 32768;
        NSMutableData* data = [NSMutableData dataWithCapacity:length * sizeof(UInt16)];
        UInt16* bytes = (UInt16*)data.bytes;
        for (NSUInteger n = 0; n < length; ++n)
        {
            bytes[n] = n;
        }

        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileDenied
{
    if ([self setupTest])
    {
        [self useResponseSet:@"stor denied"];
        NSURL* url = [self URLForPath:@"/BaseCKProtocolTests/test.txt"]; // should fail as it's at the root - we put it in a subfolder just in case
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error);
            // TODO: Test for specific error

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtRootReallyGoesIntoRoot
{
    // I found we were constructing URLs wrong for the paths like: /example.txt
    // Such files were ending up in the home folder, rather than root

    if ([self setupTest] && [self usingMockServerWithProtocol:@"ftp"]) // only perform this test for FTP using MockServer
    {
        [self useResponseSet:@"chroot fail"];
        NSURL* url = [self URLForPath:@"/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            // Make sure the file went into root, rather than home
            // This could be done by changing directory to /, or storing directly to /test.txt
            [self.server.transcript enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(KMSTranscriptEntry *aTranscriptEntry, NSUInteger idx, BOOL *stop) {

                // Search back for the STOR command
                if (aTranscriptEntry.type == KMSTranscriptInput && [aTranscriptEntry.value hasPrefix:@"STOR "])
                {
                    *stop = YES;

                    // Was the STOR command itself valid?
                    if ([aTranscriptEntry.value hasPrefix:@"STOR /test.txt"])
                    {

                    }
                    else
                    {
                        // Search back for the preceeding CWD command
                        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, idx)];
                        __block BOOL haveChangedDirectory = NO;

                        [self.server.transcript enumerateObjectsAtIndexes:indexes options:NSEnumerationReverse usingBlock:^(KMSTranscriptEntry *aTranscriptEntry, NSUInteger idx, BOOL *stop) {

                            if (aTranscriptEntry.type == KMSTranscriptInput && [aTranscriptEntry.value hasPrefix:@"CWD "])
                            {
                                *stop = YES;
                                haveChangedDirectory = YES;
                                XCTAssertTrue([aTranscriptEntry.value isEqualToString:@"CWD /\r\n"], @"libcurl changed to the wrong directory: %@", aTranscriptEntry.value);
                            }
                        }];

                        XCTAssertTrue(haveChangedDirectory, @"libcurl never changed directory");
                    }
                }
            }];

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileSerialThrash
{
    // Create the same file multiple times in a row. This has been tending to fail weirdly when testing CURLTransfer directly

    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* url = [self URLForTestFile1];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

            XCTAssertNil(error, @"got unexpected error %@", error);

            [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                XCTAssertNil(error, @"got unexpected error %@", error);

                [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                    XCTAssertNil(error, @"got unexpected error %@", error);

                    [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                        XCTAssertNil(error, @"got unexpected error %@", error);
                        [self pause];
                    }];
                }];
            }];
        }];

        [self runUntilPaused];
    }
}

- (void)testRenameFileAtURL
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSString* extension = [url pathExtension];
        NSString* newName = [@"renamed" stringByAppendingPathExtension:extension];
        NSURL* renamed = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:newName];

        // rename file
        [self.manager renameItemAtURL:url toFilename:newName completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);

            if (!self.useMockServer)
            {
                // try to remove original file - if we don't get an error here it's a hint that the move didn't work (although sadly for SFTP we won't get an error currently, so it's not conclusive)
                [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {
                    BOOL errorCanBeNil = [self usingMockServerWithProtocol:@"sftp"]; // SFTP is a bit crap at reporting errors
                    XCTAssertTrue([self checkIsRemovalError:error nilAllowed:errorCanBeNil], @"expected removal error, got %@", error);

                    // try to remove renamed file - again, if we get an error here it's a big hint that the move didn't work
                    [self.manager removeItemAtURL:renamed completionHandler:^(NSError *error) {
                        XCTAssertNil(error, @"got unexpected error %@", error);
                        [self pause];
                    }];
                }];
            }
            else
            {
                [self pause];
            }
        }];
        
        [self runUntilPaused];
    }
}

- (void)testRemoveFileAtURL
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testRemoveFileAtURLBadURL
{
    [self enumerateWithBadURLS:^(NSURL *url) {
        [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testRemoveFileAtURLFileDoesnExist
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"delete fails"];
        NSURL* url = [self URLForTestFile1];
        [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {

            BOOL errorCanBeNil = [self usingProtocol:@"sftp"]; // SFTP is a bit crap at reporting errors
            XCTAssertTrue([self checkIsRemovalError:error nilAllowed:errorCanBeNil], @"expected removal error, got %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }

}

- (void)testRemoveFileAtURLContainingFolderDoesnExist
{
    if ([self setupTest])
    {
        [self removeTestDirectory];
        [self useResponseSet:@"delete fails missing directory"];
        NSURL* url = [self URLForTestFile1];
        [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {
            BOOL errorCanBeNil = [self usingMockServerWithProtocol:@"sftp"]; // SFTP is a bit crap at reporting errors
            XCTAssertTrue([self checkIsRemovalError:error nilAllowed:errorCanBeNil], @"expected removal error, got %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }

}

- (void)testRemoveFileAtURLBadLogin
{
    if ([self setupTest] && [self protocolUsesAuthentication])
    {
        [self useBadLogin];
        NSURL* url = [self URLForTestFile1];
        [self.manager removeItemAtURL:url completionHandler:^(NSError *error) {

            XCTAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetUnknownAttributes
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ @"test" : @"test" };
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFile
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFileBadURL
{
    NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
    [self enumerateWithBadURLS:^(NSURL *url) {
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error");
            [self pause];
        }];
        [self runUntilPaused];
    }];
}

- (void)testSetAttributesOnFolder
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];
        NSURL* url = [self URLForTestFolder];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0777)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFileDoesntExist
{
    if ([self setupTest])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            BOOL errorCanBeNil = [self usingMockServerWithProtocol:@"webdav"]; // no errors because it's not supported in WebDAV
            XCTAssertTrue([self checkIsUpdateError:error nilAllowed:errorCanBeNil], @"expected file can't write error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFolderDoesntExist
{
    if ([self setupTest])
    {
        [self removeTestDirectory];
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForTestFolder];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            BOOL errorCanBeNil = [self usingMockServerWithProtocol:@"webdav"]; // no errors because it's not supported in WebDAV
            XCTAssertTrue([self checkIsUpdateError:error nilAllowed:errorCanBeNil], @"expected file can't write error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesCHMODNotUnderstood
{
    if (self.useMockServer && [self setupTest]) // no way to test this on a real server (unless it actually doesn't understand CHMOD of course...)
    {
        [self useResponseSet:@"chmod not understood"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesCHMODUnsupported
{
    if (self.useMockServer && [self setupTest]) // no way to test this on a real server (unless it actually doesn't support CHMOD of course...)
    {
        [self useResponseSet:@"chmod unsupported"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            XCTAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOperationNotPermitted
{
    if (self.useMockServer && [self setupTest]) // can't reliably target a file that we don't have permission to change on a real server, since we don't know what it has
    {
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            NSString* domain = error.domain;
            if ([domain isEqualToString:NSURLErrorDomain])
            {
                // get NSURLErrorNoPermissionsToReadFile if the path doesn't exist or isn't readable on the server
                XCTAssertTrue(error.code == NSURLErrorNoPermissionsToReadFile, @"unexpected error %@", error);
            }
            else if ([domain isEqualToString:NSCocoaErrorDomain])
            {
                XCTAssertTrue((error.code == NSFileWriteUnknownError || // FTP has no hard way to know it was a permissions error
                              error.code == NSFileWriteNoPermissionError), @"unexpected error %@", error);
            }
            else
            {
                XCTFail(@"unexpected error %@", error);
            }

            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testBadLoginThenGoodLogin
{
    if ([self setupTest] && [self protocolUsesAuthentication])
    {
        [self removeTestDirectory];
        [self useBadLogin];
        
        NSURL* url = [self URLForTestFolder];
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            
            XCTAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            
            self.user = self.originalUser;
            [self useResponseSet:@"default"];
            
            [self.manager createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
                XCTAssertNil(error, @"got unexpected error %@", error);
                
                [self pause];
            }];
        }];

        [self runUntilPaused];
    }
}

@end
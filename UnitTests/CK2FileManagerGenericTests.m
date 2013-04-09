//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "KMSServer.h"
#import "KMSTranscriptEntry.h"

#import "CK2FileManagerWithTestSupport.h"

#import "CK2Authentication.h"

#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerGenericTests : CK2FileManagerBaseTests

@property (strong, nonatomic) NSString* responsesToUse;

@end

@implementation CK2FileManagerGenericTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

static NSString* gResponsesToUse = nil;

+ (id) defaultTestSuite
{
    NSArray* responses = @[@"ftp", @"sftp"];

    SenTestSuite* result = [[SenTestSuite alloc] initWithName:[NSString stringWithFormat:@"%@Collection", NSStringFromClass(self)]];
    for (NSString* name in responses)
    {
        // in order to re-use the default SenTest mechanism for building up a suite of tests, we set some global variables
        // to indicate the test configuration we want, then call on to the defaultTestSuite to get a set of tests using that configuration.
        gResponsesToUse = name;
        SenTestSuite* suite = [[SenTestSuite alloc] initWithName:[NSString stringWithFormat:@"%@Using%@", NSStringFromClass(self), [name uppercaseString]]];
        [suite addTest:[super defaultTestSuite]];
        [result addTest:suite];
        [suite release];
    }

    return [result autorelease];
}

- (id)initWithInvocation:(NSInvocation *)anInvocation
{
    if ((self = [super initWithInvocation:anInvocation]) != nil)
    {
        // store the value of the globals here, since they'll potentially be different by the time we're actually run
        self.responsesToUse = gResponsesToUse;
    }

    return self;
}

- (void)dealloc
{
    [_responsesToUse release];

    [super dealloc];
}

- (BOOL)setup
{
    BOOL result = ([self setupSessionWithResponses:self.responsesToUse]);
    self.server.data = [ExampleListing dataUsingEncoding:NSUTF8StringEncoding];

    return result;
}

- (void)tearDown
{
    if (self.session)
    {
        [self removeTestDirectory];
    }

    [super tearDown];
}

- (void)useBadLogin
{
    self.user = @"bad";
    [self useResponseSet:@"bad login"];
}

#pragma mark - Result Checking Support

- (void)checkURL:(NSURL*)url isNamed:(NSString*)name
{
    STAssertTrue([[url lastPathComponent] isEqualToString:name], @"URL %@ name was wrong, expected %@", url, name);
}

- (void)checkURLs:(NSMutableArray*)urls containItemNamed:(NSString*)name
{
    BOOL found = NO;
    NSUInteger count = [urls count];
    for (NSUInteger n = 0; n < count; ++n)
    {
        NSURL* url = urls[n];
        if ([[url lastPathComponent] isEqualToString:name])
        {
            [urls removeObjectAtIndex:n];
            found = YES;
            break;
        }
    }

    STAssertTrue(found, @"unexpected item with name %@", name);
}


#pragma mark - Tests

- (void)testMakeRemoveOnly
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];
        [self removeTestDirectory];
    }
}

- (void)testContentsOfDirectoryAtURL
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            if (error)
            {
                STFail(@"got error %@", error);
            }
            else
            {
                NSUInteger count = [contents count];
                STAssertTrue(count == 2, @"should have two results, had %ld", count);
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

- (void)testContentsOfDirectoryAtURLBadLogin
{
    if ([self setup])
    {
        [self useBadLogin];

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            STAssertTrue([contents count] == 0, @"shouldn't get content");

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testEnumerateContentsOfURL
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];

        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
        NSMutableArray* expectedURLS = [NSMutableArray arrayWithArray:@[
                                        url,
                                        [self URLForTestFile1],
                                        [self URLForTestFile2]
                                        ]];

        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            NSLog(@"got item %@", item);
            [self checkURLs:expectedURLS containItemNamed:[item lastPathComponent]];
        } completionHandler:^(NSError *error) {
            if (error)
            {
                STFail(@"got error %@", error);
            }
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testEnumerateContentsOfURLBadLogin
{
    if ([self setup])
    {
        [self useBadLogin];
        NSURL* url = [self URLForTestFolder];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {

            STFail(@"shouldn't get any items");

        } completionHandler:^(NSError *error) {

            STAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            [self pause];

        }];

        [self runUntilPaused];
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setup])
    {
        [self removeTestDirectory];

        NSURL* url = [self URLForTestFolder];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testCreateDirectoryAtURLAlreadyExists
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"mkdir fail"];

        NSURL* url = [self URLForTestFolder];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertTrue([self checkIsFileCantWriteError:error], @"expected file can't write error, got %@", error);

            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testCreateDirectoryAtURLBadLogin
{
    if ([self setup])
    {
        [self useBadLogin];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {

            STAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURL
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* url = [self URLForTestFile1];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURL2
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* temp = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        NSURL* source = [temp URLByAppendingPathComponent:@"test.txt"];
        NSError* error = nil;
        STAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        NSURL* url = [self URLForTestFile1];

        [self.session createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        STAssertTrue([[NSFileManager defaultManager] removeItemAtURL:source error:&error], @"failed to remove temporary file with error %@", error);
    }
}

- (void)testUploadOver16k
{
    if ([self setup])
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

        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileDenied
{
    if ([self setup])
    {
        [self useResponseSet:@"stor denied"];
        NSURL* url = [self URLForPath:@"/CK2FileManagerGenericTests/test.txt"]; // should fail as it's at the root - we put it in a subfolder just in case
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, nil);
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

    if ([self.responsesToUse isEqualToString:@"ftp"] && self.useMockServer && [self setup]) // only perform this test for FTP using MockServer
    {
        [self useResponseSet:@"chroot fail"];
        NSURL* url = [self URLForPath:@"/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

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
                                STAssertTrue([aTranscriptEntry.value isEqualToString:@"CWD /\r\n"], @"libcurl changed to the wrong directory: %@", aTranscriptEntry.value);
                            }
                        }];

                        STAssertTrue(haveChangedDirectory, @"libcurl never changed directory");
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
    // Create the same file multiple times in a row. This has been tending to fail weirdly when testing CURLHandle directly

    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];

        NSURL* url = [self URLForTestFile1];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

            STAssertNil(error, @"got unexpected error %@", error);

            [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                STAssertNil(error, @"got unexpected error %@", error);

                [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                    STAssertNil(error, @"got unexpected error %@", error);

                    [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {

                        STAssertNil(error, @"got unexpected error %@", error);
                        [self pause];
                    }];
                }];
            }];
        }];

        [self runUntilPaused];
    }
}

- (void)testMoveFileAtURL
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSString* extension = [url pathExtension];
        NSString* newName = [@"renamed" stringByAppendingPathExtension:extension];
        NSURL* renamed = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:newName];

        // rename file
        [self.session renameItemAtURL:url withFilename:newName completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            // try to remove original file - if we don't get an error here it's a hint that the move didn't work (although sadly for SFTP we won't get an error currently, so it's not conclusive)
            [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
                STAssertTrue([self checkNoErrorOrIsFileCantWriteError:error], @"unexpected error %@", error);

                // try to remove renamed file - again, if we get an error here it's a big hint that the move didn't work
                [self.session removeItemAtURL:renamed completionHandler:^(NSError *error) {
                    STAssertNil(error, @"got unexpected error %@", error);
                    [self pause];
                }];
            }];
        }];
    }

    [self runUntilPaused];
}

- (void)testRemoveFileAtURL
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testRemoveFileAtURLFileDoesnExist
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"delete fail"];
        NSURL* url = [self URLForTestFile1];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            
            STAssertTrue([self checkNoErrorOrIsFileCantWriteError:error], @"expected file can't write error, got %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }

}

- (void)testRemoveFileAtURLContainingFolderDoesnExist
{
    if ([self setup])
    {
        [self removeTestDirectory];
        [self useResponseSet:@"cwd fail"];
        NSURL* url = [self URLForTestFile1];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            STAssertTrue([self checkNoErrorOrIsFileNotFoundError:error], @"expected file can't write error, got %@", error);

            [self pause];
        }];

        [self runUntilPaused];
    }

}

- (void)testRemoveFileAtURLBadLogin
{
    if ([self setup])
    {
        [self useBadLogin];
        NSURL* url = [self URLForTestFile1];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {

            STAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetUnknownAttributes
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ @"test" : @"test" };
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFile
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:YES];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFolder
{
    if ([self setup])
    {
        [self makeTestDirectoryWithFiles:NO];
        NSURL* url = [self URLForTestFolder];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0777)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFileDoesntExist
{
    if ([self setup])
    {
        [self useResponseSet:@"chmod not permitted"];
        [self makeTestDirectoryWithFiles:NO];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertTrue([self checkIsFileCantWriteError:error], @"expected file can't write error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOnFolderDoesntExist
{
    if ([self setup])
    {
        [self removeTestDirectory];
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForTestFolder];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertTrue([self checkIsFileCantWriteError:error], @"expected file can't write error, got %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesCHMODNotUnderstood
{
    if (self.useMockServer && [self setup]) // no way to test this on a real server (unless it actually doesn't understand CHMOD of course...)
    {
        [self useResponseSet:@"chmod not understood"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesCHMODUnsupported
{
    if (self.useMockServer && [self setup]) // no way to test this on a real server (unless it actually doesn't support CHMOD of course...)
    {
        [self useResponseSet:@"chmod unsupported"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOperationNotPermitted
{
    if (self.useMockServer && [self setup]) // can't reliably target a file that we don't have permission to change on a real server, since we don't know what it has
    {
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForTestFile1];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            NSString* domain = error.domain;
            if ([domain isEqualToString:NSURLErrorDomain])
            {
                // get NSURLErrorNoPermissionsToReadFile if the path doesn't exist or isn't readable on the server
                STAssertTrue(error.code == NSURLErrorNoPermissionsToReadFile, @"unexpected error %@", error);
            }
            else if ([domain isEqualToString:NSCocoaErrorDomain])
            {
                STAssertTrue((error.code == NSFileWriteUnknownError || // FTP has no hard way to know it was a permissions error
                              error.code == NSFileWriteNoPermissionError), @"unexpected error %@", error);
            }
            else
            {
                STFail(@"unexpected error %@", error);
            }

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testBadLoginThenGoodLogin
{
    if ([self setup])
    {
        [self removeTestDirectory];
        [self useBadLogin];

        NSURL* url = [self URLForTestFolder];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            
            STAssertTrue([self checkIsAuthenticationError:error], @"was expecting authentication error, got %@", error);
            
            self.user = self.originalUser;
            [self useResponseSet:@"default"];
            
            [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                
                [self pause];
            }];
        }];
    }
    
    [self runUntilPaused];
}

@end
//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "KMSServer.h"
#import "KMSTranscriptEntry.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>
#import <CURLHandle/CURLHandle.h>

@class CK2FileManagerFTPTests;
@interface CleanupDelegate : CK2FileManager<CK2FileManagerDelegate>

@property (strong, nonatomic) CK2FileManagerFTPTests* tests;

@end

@interface CK2FileManagerFTPTests : CK2FileManagerBaseTests

@property (strong, nonatomic) NSString* responsesToUse;

@end

@implementation CleanupDelegate

+ (CleanupDelegate*)delegateWithTest:(CK2FileManagerFTPTests*)tests
{
    CleanupDelegate* result = [[CleanupDelegate alloc] init];
    result.tests = tests;

    return [result autorelease];
}

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    else
    {
        NSURLCredential* credential = [NSURLCredential credentialWithUser:self.tests.originalUser password:self.tests.originalPassword persistence:NSURLCredentialPersistenceNone];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }
}

@end


@implementation CK2FileManagerFTPTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

static const BOOL kMakeRemoveTestFilesOnMockServer = YES;

static NSString* gResponsesToUse = nil;

+ (id) defaultTestSuite
{
    NSArray* responses = @[@"ftp" /*, @"sftp"*/];

    SenTestSuite* result = [[SenTestSuite alloc] initWithName:[NSString stringWithFormat:@"%@Collection", NSStringFromClass(self)]];
    for (NSString* name in responses)
    {
        // in order to re-use the default SenTest mechanism for building up a suite of tests, we set some global variables
        // to indicate the test configuration we want, then call on to the defaultTestSuite to get a set of tests using that configuration.
        gResponsesToUse = name;
        SenTestSuite* suite = [[SenTestSuite alloc] initWithName:name];
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

- (void)checkIsAuthenticationError:(NSError*)error
{
    STAssertNotNil(error, @"should get error");
    STAssertTrue([error.domain isEqualToString:NSURLErrorDomain], @"unexpected domain %@", error.domain);
    STAssertTrue(error.code == NSURLErrorUserAuthenticationRequired || error.code == NSURLErrorUserCancelledAuthentication, @"should get authentication error, got %@ instead", error);
}

- (void)checkNoErrorOrFileExistsError:(NSError*)error
{
    if (error)
    {
        STAssertTrue([error.domain isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", error.domain);
        STAssertTrue(error.code == NSFileWriteUnknownError, @"unexpected error code %ld", error.code);
    }
}

- (void)checkIsFileCantWriteError:(NSError*)error
{
    STAssertNotNil(error, @"should get error");
    STAssertTrue([error.domain isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", error.domain);
    STAssertTrue(error.code == NSFileWriteUnknownError, @"unexpected error code %ld", error.code);
}

- (void)checkIsFileNotFoundError:(NSError*)error
{
    STAssertNotNil(error, @"should get error");
    STAssertTrue([error.domain isEqualToString:NSURLErrorDomain], @"unexpected error domain %@", error.domain);
    STAssertTrue(error.code == NSURLErrorNoPermissionsToReadFile, @"unexpected error code %ld", error.code);
}

#pragma mark - Test File Support

- (NSURL*)URLForTestFolder
{
    return [self URLForPath:@"CK2FileManagerFTPTests"];
}

- (NSURL*)URLForTestFile1
{
    return [[self URLForTestFolder] URLByAppendingPathComponent:@"file1.txt"];
}

- (NSURL*)URLForTestFile2
{
    return [[self URLForTestFolder] URLByAppendingPathComponent:@"file2.txt"];
}

- (void)makeTestDirectoryWithFiles:(BOOL)withFiles
{
    // we do report errors from here, since something going wrong is likely to affect the result of the test that called us
    
    if (kMakeRemoveTestFilesOnMockServer || !self.useMockServer)
    {
        // if we don't want the test files, remove everything first
        if (!withFiles)
        {
            [self removeTestDirectory];
        }

        NSLog(@"<<<< Making Test Directory");

        CK2FileManager* session = [[CK2FileManager alloc] init];
        session.delegate = [CleanupDelegate delegateWithTest:self];

        // make the folder if necessary
        NSURL* url = [self URLForTestFolder];
        [session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            [self checkNoErrorOrFileExistsError:error];

            // if we want the files, make them too
            if (withFiles)
            {
                NSData* contents = [@"This is a test file" dataUsingEncoding:NSUTF8StringEncoding];
                [session createFileAtURL:[self URLForTestFile1] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                    [self checkNoErrorOrFileExistsError:error];
                    [session createFileAtURL:[self URLForTestFile2] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                        [self checkNoErrorOrFileExistsError:error];
                        [self pause];
                        NSLog(@"<<<< Made Test Files");
                    }];
                }];
            }
            else
            {
                [self pause];
            }
            NSLog(@"<<<< Made Test Directory");
        }];

        [self runUntilPaused];

        [session release];
    }
}

- (void)removeTestDirectory
{
    if (kMakeRemoveTestFilesOnMockServer || !self.useMockServer)
    {
        NSLog(@"<<<< Removing Test Files");
        // suppress the transcript for this stuff
        NSMutableString* saved = self.transcript;
        self.transcript = nil;

        CK2FileManager* session = [[CK2FileManager alloc] init];
        session.delegate = [CleanupDelegate delegateWithTest:self];

        // we don't care about errors here, we just want to do our best to clean up after any tests
        [session removeItemAtURL:[self URLForTestFile2] completionHandler:^(NSError *error) {
            [session removeItemAtURL:[self URLForTestFile1] completionHandler:^(NSError *error) {
                [session removeItemAtURL:[self URLForTestFolder] completionHandler:^(NSError *error) {
                    [self pause];

                    // restore the transcript
                    self.transcript = saved;
                    NSLog(@"<<<< Removed Test Files");
                }];
            }];
        }];

        [self runUntilPaused];
        [session release];
    }
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

            [self checkIsAuthenticationError:error];
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
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
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
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {

            STFail(@"shouldn't get any items");

        } completionHandler:^(NSError *error) {

            [self checkIsAuthenticationError:error];
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
    if ([self setupSessionWithResponses:@"ftp"])
    {
        [self makeTestDirectoryWithFiles:NO];
        [self useResponseSet:@"mkdir fail"];
        
        NSURL* url = [self URLForTestFolder];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            [self checkIsFileCantWriteError:error];
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

            [self checkIsAuthenticationError:error];
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

- (void)testCreateFileDenied
{
    if ([self setup])
    {
        [self useResponseSet:@"stor denied"];
        NSURL* url = [self URLForPath:@"/CK2FileManagerFTPTests/test.txt"]; // should fail as it's at the root - we put it in a subfolder just in case
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
    
    if ([self setup])
    {
        [self useResponseSet:@"chroot jail"];
        NSURL* url = [self URLForPath:@"/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"got unexpected error %@", error);
            
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
                        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, index)];
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
            [self checkIsFileCantWriteError:error];

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
            [self checkIsFileNotFoundError:error];

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

            [self checkIsAuthenticationError:error];
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
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
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
            [self checkIsFileCantWriteError:error];
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
            [self checkIsFileCantWriteError:error];
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

            [self checkIsAuthenticationError:error];

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
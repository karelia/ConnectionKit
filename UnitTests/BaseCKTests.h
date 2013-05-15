//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "KMSTestCase.h"
#import "KMSState.h"
#import "CK2FileManager.h"

@interface BaseCKTests : KMSTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) CK2FileManager* manager;
@property (assign, atomic) KMSState state;
@property (strong, nonatomic) NSMutableString* transcript;
@property (readonly, nonatomic) NSString* protocol;
@property (assign, nonatomic) BOOL useMockServer;
@property (strong, nonatomic) NSString* originalUser;
@property (strong, nonatomic) NSString* originalPassword;


- (BOOL)setupTest;
- (BOOL)isSetup;
- (BOOL)protocolUsesAuthentication;
- (NSURL*)temporaryFolder;

- (BOOL)usingProtocol:(NSString*)type;
- (BOOL)usingMockServerWithProtocol:(NSString*)type;
- (void)useBadLogin;
- (NSData*)mockServerDirectoryListingData;

#pragma mark - Test File Support

- (NSURL*)URLForTestFolder;
- (NSURL*)URLForTestFile1;
- (NSURL*)URLForTestFile2;
- (void)makeTestDirectoryWithFiles:(BOOL)withFiles;
- (void)removeTestDirectory;

#pragma mark - Checking

- (void)checkURL:(NSURL*)url isNamed:(NSString*)name;
- (void)checkURLs:(NSMutableArray*)urls containItemNamed:(NSString*)name;
- (BOOL)checkIsAuthenticationError:(NSError*)error;
- (BOOL)checkIsCreationError:(NSError*)error nilAllowed:(BOOL)nilAllowed;
- (BOOL)checkIsRemovalError:(NSError*)error nilAllowed:(BOOL)nilAllowed;
- (BOOL)checkIsUpdateError:(NSError*)error nilAllowed:(BOOL)nilAllowed;
- (BOOL)checkIsMissingError:(NSError*)error nilAllowed:(BOOL)nilAllowed;
@end

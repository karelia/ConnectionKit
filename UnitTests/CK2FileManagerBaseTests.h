//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "KMSTestCase.h"
#import "KMSState.h"
#import "CK2FileManager.h"

@interface CK2FileManagerBaseTests : KMSTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) CK2FileManager* session;
@property (assign, atomic) KMSState state;
@property (strong, nonatomic) NSMutableString* transcript;
@property (strong, nonatomic) NSString* type;
@property (assign, nonatomic) BOOL useMockServer;
@property (strong, nonatomic) NSString* originalUser;
@property (strong, nonatomic) NSString* originalPassword;
@property (strong, nonatomic) NSString* extendedName;


- (NSURL*)temporaryFolder;
- (BOOL)setupSession;
- (BOOL)setupSessionWithResponses:(NSString*)responsesFile;

#pragma mark - Test File Support

- (NSURL*)URLForTestFolder;
- (NSURL*)URLForTestFile1;
- (NSURL*)URLForTestFile2;
- (void)makeTestDirectoryWithFiles:(BOOL)withFiles;
- (void)removeTestDirectory;

#pragma mark - Error Checking

- (BOOL)checkIsAuthenticationError:(NSError*)error;
- (BOOL)checkNoErrorOrFileExistsError:(NSError*)error;
- (BOOL)checkIsFileCantWriteError:(NSError*)error;
- (BOOL)checkNoErrorOrIsFileCantWriteError:(NSError*)error;
- (BOOL)checkIsFileNotFoundError:(NSError*)error;
- (BOOL)checkNoErrorOrIsFileNotFoundError:(NSError*)error;
@end

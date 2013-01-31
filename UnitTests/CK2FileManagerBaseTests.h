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
@property (assign, nonatomic) BOOL useMockServer;

- (NSURL*)temporaryFolder;
- (BOOL)setupSession;
- (BOOL)setupSessionWithResponses:(NSString*)responsesFile;

@end

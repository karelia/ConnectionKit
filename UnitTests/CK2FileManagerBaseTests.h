//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "KMSTestCase.h"
#import "CK2FileManager.h"

#define TEST_WITH_REAL_SERVER 0

@interface CK2FileManagerBaseTests : KMSTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) CK2FileManager* session;

- (BOOL)setupSessionWithRealURL:(NSURL*)realURL fakeResponses:(NSString*)responsesFile;

@end

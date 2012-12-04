//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>

#import "CK2FileManager.h"

#define TEST_WITH_REAL_SERVER 0

@class KMSServer;
@class KMSResponseCollection;

@interface CK2FileManagerBaseTests : SenTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) KMSServer* server;
@property (strong, nonatomic) CK2FileManager* session;
@property (assign, nonatomic) BOOL running;
@property (strong, nonatomic) NSString* user;
@property (strong, nonatomic) NSString* password;
@property (strong, nonatomic) KMSResponseCollection* responses;
@property (strong, nonatomic) NSURL* url;
@property (strong, nonatomic) NSMutableString* transcript;

- (BOOL)setupSessionWithRealURL:(NSURL*)realURL fakeResponses:(NSString*)responsesFile;
- (void)useResponseSet:(NSString*)name;

- (NSURL*)URLForPath:(NSString*)path;

- (void)runUntilStopped;
- (void)stop;
- (void)pause;

@end

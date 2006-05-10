//
//  LocalConnectionTest.m
//  Connection
//
//  Created by olivier on 4/24/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "FileConnectionTest.h"


@implementation FileConnectionTest

- (NSString *)connectionName
{
	return @"File";
}

- (void) testConnectWithBadHost
{
  //NA
}

- (void) testConnectWithBadUserName
{
  //NA
}

- (void) testConnectWithBadpassword
{
  //NA
}

- (void) testConnect
{
  [super testConnect];
  
  //check that the file manager has its path set to the same thing as what the connection returns
  //
  STAssertEqualObjects([[connection valueForKey: @"myFileManager"] currentDirectoryPath], [connection currentDirectory], @"path not synchronized between filemanager and connection");
}
@end

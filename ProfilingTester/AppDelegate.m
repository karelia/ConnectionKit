//
//  AppDelegate.m
//  ProfilingTester
//
//  Created by Sam Deane on 27/03/2013.
//
//

#import "AppDelegate.h"
#import <ConnectionKit/Connection.h>

@implementation AppDelegate

- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application

    CK2FileManager* fm = [[CK2FileManager alloc] init];

    for (NSUInteger n = 0; n < 100; ++n)
    {
        NSURL* url = [NSURL URLWithString:@"ftp://test:test@ftp.secureftp-test.com/"];

        [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[] options:NSDirectoryEnumerationSkipsHiddenFiles completionHandler:^(NSArray *contents, NSError *error) {
            NSLog(@"contents: %@  error: %@", contents, error);
        }];
    }

    [fm release];

}

@end

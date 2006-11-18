//
//  DropletLauncher.m
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//
#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[])
{
    return NSApplicationMain(argc,  (const char **) argv);
}

@interface DropletLauncherDelegate : NSObject
{
	
}

@end

@implementation DropletLauncherDelegate

- (void)application:(NSApplication *)app openFiles:(NSArray *)files
{
	NSString *dropletCreator = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CKApplication"];
	NSString *applicationPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:dropletCreator];
	NSString *dyldPath = [[applicationPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Frameworks"];
	NSString *ckFrameworkPath = [[dyldPath stringByAppendingPathComponent:@"Connection"] stringByAppendingPathExtension:@"framework"];
	NSString *dropletPath = [[NSBundle bundleWithPath:ckFrameworkPath] pathForResource:@"DropletHelper" ofType:@"app"];
	NSString *path = [[NSBundle bundleWithPath:dropletPath] executablePath];
	
	if (!path)
	{
		NSRunAlertPanel(NSLocalizedString(@"Bad Droplet", @"error"),
						NSLocalizedString(@"This droplet is missing the original application that created it. You will need to reinstall the original application.", @"error"),
						NSLocalizedString(@"Quit", @"error"),
						nil,
						nil);
		[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0];
		return;
	}
	
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:path];
	NSMutableArray *args = [NSMutableArray arrayWithObject:[[NSBundle mainBundle] pathForResource:@"configuration" ofType:@"ckhost"]];
	[args addObjectsFromArray:files];
	[task setArguments:args];
	[task launch];
	
    [task release];
	[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

@end


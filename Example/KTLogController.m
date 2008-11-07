#import "KTLogController.h"
#import "KTLog.h"

@interface KTLogLevelTransformer : NSValueTransformer
{
	
}
@end

@interface NSStringToAttributedString : NSValueTransformer
{
	
}
@end

@implementation KTLogController

+ (void)initialize
{
	[NSValueTransformer setValueTransformer:[[[KTLogLevelTransformer alloc] init] autorelease]
									forName:@"KTLogLevelTransformer"];
	[NSValueTransformer setValueTransformer:[[[NSStringToAttributedString alloc] init] autorelease]
									forName:@"NSStringToAttributedString"];
}

- (void)awakeFromNib
{
	NSString *log = [[NSUserDefaults standardUserDefaults] objectForKey:@"LastOpened"];
	if (log && [[NSFileManager defaultManager] fileExistsAtPath:log])
	{
		[self willChangeValueForKey:@"entries"];
		myEntries = [[KTLogger entriesWithLogFile:log] retain];
		[self didChangeValueForKey:@"entries"];
	}
	
	[[[oTable tableColumnWithIdentifier:@"f"] dataCell] setLineBreakMode: NSLineBreakByTruncatingHead];
}

- (NSArray *)entries
{
	return myEntries;
}

- (void)open:(id)sender
{
	NSOpenPanel *op = [NSOpenPanel openPanel];
	
	[op beginSheetForDirectory:nil
						  file:nil
						 types:[NSArray arrayWithObject:@"ktlog"]
				modalForWindow:oWindow
				 modalDelegate:self
				didEndSelector:@selector(open:rc:ci:) 
				   contextInfo:nil];
}

- (void)open:(NSOpenPanel *)op rc:(int)rc ci:(id)ci
{
	if (rc == NSOKButton)
	{
		[myEntries autorelease];
		[self willChangeValueForKey:@"entries"];
		myEntries = [[KTLogger entriesWithLogFile:[op filename]] retain];
		[self didChangeValueForKey:@"entries"];
		
		[[NSUserDefaults standardUserDefaults] setObject:[op filename] forKey:@"LastOpened"];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
}

@end

@implementation NSStringToAttributedString

+ (BOOL)allowsReverseTransformation { return NO; }

- (id)transformedValue:(id)value 
{
	return [[[NSAttributedString alloc] initWithString:value] autorelease];
}

@end

@implementation KTLogLevelTransformer

+ (BOOL)allowsReverseTransformation { return NO; }

- (id)transformedValue:(id)value 
{
	return [[[KTLogger sharedLogger] levelNames] objectAtIndex:[value intValue]];
}

@end

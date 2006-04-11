/*
 Copyright (c) 2006, Greg Hulands <ghulands@framedphotographics.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "KTLog.h"
#import <stdarg.h>

@interface KTLogger (Private)

- (id)init;
+ (id)sharedLogger;
- (void)logFile:(char *)file lineNumber:(int)line loggingDomain:(NSString *)domain loggingLevel:(int)level message:(NSString *)log;
- (void)setLoggingLevel:(KTLoggingLevel)level forDomain:(NSString *)domain;

@end

static KTLogger *_sharedLogger = nil;
static unsigned long long KTLogMaximumLogSize = 5242880; // 5MB
static BOOL KTLogToConsole = YES;
static id _loggingDelegate = nil;

static NSString *KTLevelMap[] = {
	@"KTLogOff",
	@"INFO",
	@"WARN",
	@"ERROR",
	@"FATAL",
	@"DEBUG"
};

@implementation KTLogger

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	_sharedLogger = [[KTLogger alloc] init];
	[pool release];
}

+ (id)sharedLogger
{
	return _sharedLogger;
}

- (id)init
{
	if (self = [super init])
	{
		myLock = [[NSLock alloc] init];
		myLoggingLevels = [[NSMutableDictionary dictionary] retain];
		// load in from user defaults
		NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] objectForKey:@"KTLoggingLevels"];
		if (defaults)
		{
			[myLoggingLevels addEntriesFromDictionary:defaults];
		}
	}
	return self;
}

- (id)retain { return self; }
- (id)autorelease { return self; }
- (oneway void)release { }

+ (void)setDelegate:(id)delegate
{
	if ([delegate respondsToSelector:@selector(logger:logged:)])
	{
		[_loggingDelegate autorelease];
		_loggingDelegate = [delegate retain];
	}
}

+ (void)setMaximumLogSize:(unsigned long long)bytes
{
	KTLogMaximumLogSize = bytes;
}

+ (void)setLogToConsole:(BOOL)flag
{
	KTLogToConsole = flag;
}

+ (void)setLoggingLevel:(KTLoggingLevel)level forDomain:(NSString *)domain
{
	[[KTLogger sharedLogger] setLoggingLevel:level forDomain:domain];
}

- (void)setLoggingLevel:(KTLoggingLevel)level forDomain:(NSString *)domain
{
	[myLock lock];
	NSNumber *originalLevel = [myLoggingLevels objectForKey:domain];
	if (!originalLevel)
	{
		originalLevel = [NSNumber numberWithInt:level];
		[myLoggingLevels setObject:originalLevel forKey:domain];
		[[NSUserDefaults standardUserDefaults] setObject:myLoggingLevels forKey:@"KTLoggingLevels"];
	}
	
	if ([originalLevel intValue] != level)
	{
		[myLoggingLevels setObject:[NSNumber numberWithInt:level] forKey:domain];
		[[NSUserDefaults standardUserDefaults] setObject:myLoggingLevels forKey:@"KTLoggingLevels"];
	}
	[myLock unlock];
}

- (NSString *)logfileName
{
	NSString *logPath = [[NSString stringWithFormat:@"%@", NSHomeDirectory()] stringByAppendingPathComponent:@"Library/Logs/"];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	
	if (!([fm fileExistsAtPath:logPath isDirectory:&isDir] && isDir))
	{
		if (![fm createDirectoryAtPath:logPath attributes:nil])
		{
			NSLog(@"Failed to create log directory: %@", logPath);
		}
	}
	
	NSString *processName = [[NSProcessInfo processInfo] processName];
	NSString *logName = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ktlog", processName]];
	
	if (![fm fileExistsAtPath:logName])
	{
		if (![fm createFileAtPath:logName contents:[NSData data] attributes:nil])
		{
			NSLog(@"Failed to create log file at: %@", logName);
		}
	}
	
	return logName;
}

- (void)rotateLogs
{
	NSString *logPath = [[NSString stringWithFormat:@"%@", NSHomeDirectory()] stringByAppendingPathComponent:@"Library/Logs/"];
	NSFileManager *fm = [NSFileManager defaultManager];

	[myLog closeFile];
	[myLog release];
	myLog = nil;
	
	NSString *processName = [[NSProcessInfo processInfo] processName];
	int i = 0;
	NSString *logName = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%d.ktlog", processName, i]];
	
	while ([fm fileExistsAtPath:logName])
	{
		i++;
		logName = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%d.ktlog", processName, i]];
	}
	
	i++;
	NSString *from;
	NSString *to;
	
	while (i > 0)
	{
		from = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%d.ktlog", processName, i - 1]];
		to = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%d.ktlog", processName, i]];
		
		[fm movePath:from toPath:to handler:nil];
		i--;
	}
	
	from = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ktlog", processName]];
	to = [logPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%d.ktlog", processName, i]];
	[fm movePath:from toPath:to handler:nil];
}

- (void)logFile:(char *)file lineNumber:(int)line loggingDomain:(NSString *)domain loggingLevel:(int)level message:(NSString *)log
{
	[myLock lock];
	
	NSNumber *loggingLevel = [myLoggingLevels objectForKey:domain];
	KTLoggingLevel currentLevel = KTLogInfo;
	
	if (loggingLevel)
	{
		currentLevel = [loggingLevel intValue];
	}
	
	//we only log the current level or less.
	if (level > currentLevel || currentLevel == KTLogOff)
	{
		[myLock unlock];
		return;
	}
	
	NSDate *now = [NSDate date];
	NSString *filename = [NSString stringWithCString:file];
	NSNumber *lineNumber = [NSNumber numberWithInt:line];
	NSNumber *thisLevel = [NSNumber numberWithInt:level];
	
	
	NSDictionary *rec = [NSDictionary dictionaryWithObjectsAndKeys:now, @"t", filename, @"f", lineNumber, @"n", thisLevel, @"l", domain, @"d", log, @"m", nil];
	NSData *recData = [NSArchiver archivedDataWithRootObject:rec];
	
	if (!myLog)
	{
		// need to get the log file handle
		myLog = [[NSFileHandle fileHandleForWritingAtPath:[self logfileName]] retain];
	}
	
	[myLog seekToEndOfFile];
	
	unsigned len = [recData length];
	NSMutableData *entry = [NSMutableData data];
	[entry appendBytes:&len length:sizeof(unsigned)];
	[entry appendData:recData];
	
	[myLog writeData:entry];
	
	NSDictionary *logAttribs = [[NSFileManager defaultManager] fileAttributesAtPath:[self logfileName] traverseLink:YES];
	if ([[logAttribs objectForKey:NSFileSize] unsignedLongLongValue] > KTLogMaximumLogSize)
	{
		[self rotateLogs];
	}
	
	if (KTLogToConsole)
	{
		NSProcessInfo *pi = [NSProcessInfo processInfo];
		NSString *console = [NSString stringWithFormat:@"%@ %@[%d][%@:%@][%@:%d] %@\n", [now descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S.%F"
																												  timeZone:nil
																													locale:nil],
			[pi processName], [pi processIdentifier], KTLevelMap[level], domain, [filename lastPathComponent], line, log];
		fprintf(stderr, [console UTF8String]);
	}
	if (_loggingDelegate)
	{
		[_loggingDelegate logger:self logged:rec];
	}
	[myLock unlock];
}

+ (void)logFile:(char *)file lineNumber:(int)line loggingDomain:(NSString *)domain loggingLevel:(int)level format:(NSString *)log, ...
{
	va_list ap;
	va_start(ap, log);
	NSString *message = [[[NSString alloc] initWithFormat:log arguments:ap] autorelease];
	va_end(ap);
	
	[[KTLogger sharedLogger] logFile:file lineNumber:line loggingDomain:domain loggingLevel:level message:message];
}

+ (NSArray *)entriesWithLogFile:(NSString *)file
{
	NSFileHandle *log = [NSFileHandle fileHandleForReadingAtPath:file];
	NSMutableArray *entries = [NSMutableArray array];
	
	@try {
		// keep going until we throw an exception for being out of bounds
		while (1)
		{
			unsigned len;
			NSData *lenData = [log readDataOfLength:sizeof(unsigned)];
			[lenData getBytes:&len];
			NSData *archive = [log readDataOfLength:len];
			NSDictionary *record = [NSUnarchiver unarchiveObjectWithData:archive];
			[entries addObject:record];
		}
	} 
	@catch (NSException *e) {
		
	}
	[log closeFile];
	
	return entries;
}

@end

/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
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

#import <Cocoa/Cocoa.h>
#import <stdarg.h>
// This is based on the idea of MLog at http://www.borkware.com/rants/agentm/mlog/

extern NSString *KTLogKeyPrefix;
extern NSString *KTLogWildcardDomain;

// This is the main logging function / macro

#define KTLog(d, l, s, args...) [KTLogger logFile:__FILE__ lineNumber:__LINE__ loggingDomain:(d) loggingLevel:(l) format:(s) , ##args];

/*
	KTLog writes the log information to ~/Library/Logs/processName.ktlog
	It provides automatic log rolling once the filesize is over a threshold. The default file size is 5MB
 
	KTLogWarn is the default level.  Lower values are less chatty (fatal being rare), higher values are more chatty,
	with debug being the chattiest.
 
	By default KTLog will also log messages to the console (stderr)
 */

typedef enum {
	KTLogOff = 0,
	KTLogFatal,
	KTLogError,
	KTLogWarn,
	KTLogInfo,
	KTLogDebug
} KTLoggingLevel;

// Default for all levels (except KTLogWildcardDomain which is off unless you turn it to some level)

#define DEFAULT_LEVEL KTLogWarn

@interface KTLogger : NSObject 
{
	NSLock			*myLock;
	NSFileHandle	*myLog;
	
	NSMutableArray *myLoggingLevels;
	
	// Configuration Interface
	IBOutlet NSPanel		*oPanel;
	IBOutlet NSTableView	*oDomains;
}

+ (id)sharedLogger;

// Default is to log to the console (stderr)
+ (void)setLogToConsole:(BOOL)flag;
+ (void)setMaximumLogSize:(unsigned long long)bytes;
+ (void)setLoggingLevel:(KTLoggingLevel)level forDomain:(NSString *)domain;

+ (void)logFile:(char *)file lineNumber:(int)line loggingDomain:(NSString *)domain loggingLevel:(int)level format:(NSString *)log, ...;

+ (NSArray *)entriesWithLogFile:(NSString *)file;

// Allow to be called back when something is logged - useful for in application display of the log in real time
// we do retain the delegate
+ (void)setDelegate:(id)delegate;

+ (IBAction)configure:(id)sender;

// Private Methods
- (NSArray *)levelNames;
- (NSArray *)domains;

@end

@interface NSObject (KTLogDelegate)
- (void)logger:(KTLogger *)logger logged:(NSDictionary *)entry;
@end

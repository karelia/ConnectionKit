/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPTServer.h"
#import "SFTPConnection.h"
#import "CKInternalTransferRecord.h"
#import "NSArray+Connection.h"
#import "NSString+Connection.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <util.h>
#include "argcargv.h"
#include "fdwrite.h"
#include "typeforchar.h"

extern int	errno;
char **environ;

@implementation SFTPTServer

#pragma mark -
#pragma mark Getting Started / Tearing Down
+ (void)connectWithPorts:(NSArray *)ports
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSConnection *connection = [NSConnection connectionWithReceivePort:[ports objectAtIndex:0] sendPort:[ports objectAtIndex:1]];
	SFTPTServer	*serverObject = [[SFTPTServer alloc] init];
	[(SFTPConnection *)[connection rootProxy] setServerObject:serverObject];
    [serverObject release];
    
    [[NSRunLoop currentRunLoop] run];  
    [pool release];
}

- (id)init
{
	if ((self = [super init]))
	{
		directoryContents = [[NSMutableArray array] retain];
		directoryListingBufferString = [[NSMutableString string] retain];
		
		cancelflag = NO;
		sftppid = 0;
		connecting = NO;
		connected = NO;
		master = 0;
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[directoryContents release];
	[directoryListingBufferString release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Actions
- (void)forceDisconnect
{
	cancelflag = YES;
}

#pragma mark -
#pragma mark Buffer Prompt Checks
- (BOOL)buffer:(char *)buffer containsString:(char *)stringCheck
{
	if (!buffer || !stringCheck)
		return NO;
	return strstr(buffer, stringCheck) != NULL;
}

- (BOOL)buffer:(char *)buf containsAnyPrompts:(char **)prompts
{
	if (!buf)
		return NO;
	
	while (*prompts)
	{
		if (strstr(buf, *prompts) != NULL)
			return YES;
		prompts++;
	}
	return NO;
}

- (BOOL)bufferContainsPasswordPrompt:(char *)buf
{
    char *prompts[] = {
		"password",
		"Password:",
	"PASSCODE:",
	"Password for ",
	"Passcode for ",
	"CryptoCard Challenge", NULL};	
	
	return [self buffer:buf containsAnyPrompts:prompts];
}

- (BOOL)bufferContainsError:(char *)buf
{
    char *prompts[] = {
	"Permission denied",
	"Couldn't ",
	"Secure connection ",
	"No address associated with",
	"Connection refused",
	"Request for subsystem",
	"Cannot download",
	"ssh_exchange_identification",
	"Operation timed out",
	"no address associated with",
	"Error:",
	NULL};
	return [self buffer:buf containsAnyPrompts:prompts];
}	

- (BOOL)bufferContainsDirectoryListing:(char *)buf
{
	return [self buffer:buf containsString:"ls -la"];
}	

- (BOOL)unknownHostKeyPromptInBuffer:(char *)buf
{
    char *prompts[] = {"The authenticity of ", "Host key not found ", NULL};
	return [self buffer:buf containsAnyPrompts:prompts];
}

#pragma mark -
#pragma mark Buffer Parsing
- (void)parseTransferProgressString:(char *)transferProgressString
						isUploading:(BOOL)isUploading
			   forWrapperConnection:(SFTPConnection *)wrapperConnection
{	
	char *transferProgressStringCopy = strdup(transferProgressString);
	if (!transferProgressStringCopy)
		return;
	
	int tac;
	char **transferStringComponents;    
    if ((tac = argcargv(transferProgressStringCopy, &transferStringComponents)) < 5)
	{
		/* not a transfer progress line we're interested in */
		free(transferProgressStringCopy);
		return;
    }
	
	int	index;
	int percentCompleteIndex = -1;
    for (index = (tac - 1); index >= 0; index--)
	{
		if ((strrchr(transferStringComponents[index], '%')) != NULL)
		{
			/* found the %-done field */
			percentCompleteIndex = index;
			break;
		}
    }
	
    char *transferAmount = transferStringComponents[percentCompleteIndex + 1];
	char *transferSpeed = transferStringComponents[percentCompleteIndex + 2];

	char *transferTimeRemaining = (percentCompleteIndex == (tac - 5)) ? transferStringComponents[percentCompleteIndex + 3] : "--:--";	
	double progressPercentage = strtod(transferStringComponents[percentCompleteIndex], NULL);
	NSString *transferRate = [NSString stringWithUTF8String:transferSpeed];
	NSString *eta = [NSString stringWithFormat:@"%s", transferTimeRemaining];	
	
	NSString *formattedAmountString = [NSString stringWithUTF8String:transferAmount];
	char *amountCharacter;
	unsigned long long baseMultiplier = 1.0;
	if ([formattedAmountString hasSuffix:@"KB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 1);
	}
	else if ([formattedAmountString hasSuffix:@"MB"])
	{
		NSString *numberOfMBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfMBString UTF8String];
		baseMultiplier = pow(1024, 2);
	}
	else if ([formattedAmountString hasSuffix:@"GB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 3);
	}	
	else if ([formattedAmountString hasSuffix:@"TB"])
	{
		NSString *numberOfKBString = [formattedAmountString substringWithRange:NSMakeRange(0, [formattedAmountString length] - 2)];		
		amountCharacter = (char *)[numberOfKBString UTF8String];
		baseMultiplier = pow(1024, 4);
	}	
	else
		amountCharacter = transferAmount;
	
	unsigned long long amountTransferred = strtoull(amountCharacter, NULL, 0);
	amountTransferred *= baseMultiplier;
    if ([wrapperConnection numberOfUploads] > 0) 
	{
		[wrapperConnection upload:[wrapperConnection currentUpload]
					didProgressTo:progressPercentage
		withEstimatedCompletionIn:eta
			  givenTransferRateOf:transferRate
				amountTransferred:amountTransferred];
    }
	else
	{
		[wrapperConnection download:[wrapperConnection currentDownload]
					  didProgressTo:progressPercentage
		  withEstimatedCompletionIn:eta
				givenTransferRateOf:transferRate
				  amountTransferred:amountTransferred];		
    }
    
    free(transferProgressStringCopy);
}

- (void)collectListingFromMaster:(int)theMaster fileStream:(FILE *)stream forWrapperConnection:(SFTPConnection *)wrapperConnection
{
    char buf[MAXPATHLEN * 2] = { 0 };
    char tmp1[MAXPATHLEN * 2], tmp2[MAXPATHLEN * 2];
	BOOL isIncompleteLine = NO;
    
    /* make sure we're not buffering */
    setvbuf(stream, NULL, _IONBF, 0);
	
    fd_set readmask; 
	while (1)
	{
        FD_ZERO(&readmask);
        FD_SET(master, &readmask);
		
        if (select(master + 1, &readmask, NULL, NULL, NULL) < 0)
            return;
		if (!FD_ISSET(master, &readmask))
			continue;
		if (fgets((char *)buf, (MAXPATHLEN * 2), stream) == NULL)
			return;
		
		if ([self bufferContainsError:buf])
		{
			[wrapperConnection receivedErrorInServerResponse:[NSString stringWithUTF8String:buf]];
			return;
		}
		if ([self buffer:buf containsString:"<Press any key"])
		{
			fdwrite(master, " ");
			continue;
		}

		/*
		 * This is kind of nasty. We don't always get a full line
		 * from the server in the 'ls' output, so we have to check
		 * if that's the case, flag it, and append the rest of the 
		 * text after the next read from the server. Yar!
		 */
		int bufferLength = strlen(buf);
		if (strncmp("sftp>", buf, strlen("sftp>")) != 0 && buf[bufferLength - 1] != '\n')
		{
			if (strlen(buf) >= sizeof(tmp1))
			{
				NSLog(@"%s:too long", buf);
				continue;
			}
			strcpy(tmp1, buf);
			isIncompleteLine = YES;
			continue;
		}

		if (isIncompleteLine)
		{
			/* we know this is safe because they're the same buf size */
			strcpy(tmp2, buf);
			memset(buf, '\0', sizeof(buf));
			
			if (snprintf(buf, sizeof(buf), "%s%s", tmp1, tmp2) >= sizeof(buf))
				continue;
			isIncompleteLine = NO;
		}
		
		[wrapperConnection addStringToTranscript:[NSString stringWithBytesOfUnknownEncoding:buf length:strlen(buf)]];
		if (strstr(buf, "sftp>") != NULL)
		{
			memset(buf, '\0', strlen(buf));
			[wrapperConnection finishedCommand];
			if (![directoryListingBufferString rangeOfString:@"Can't ls"].location != NSNotFound)
			{
				[directoryContents removeAllObjects];
				[directoryContents addObjectsFromArray:[NSFileManager attributedFilesFromListing:directoryListingBufferString]];
			}
			[directoryListingBufferString release];
			directoryListingBufferString = [[NSMutableString alloc] init];
			return;
		}
		else
			[directoryListingBufferString appendString:[NSString stringWithUTF8String:buf]];
		memset(buf, '\0', strlen((char *)buf));
    }   
}

#pragma mark -
#pragma mark Protocol Loop
- (oneway void)connectToServerWithArguments:(NSArray *)arguments forWrapperConnection:(SFTPConnection *)sftpWrapperConnection
{
	NSString *sftpBinaryPath = [NSString pathForExecutable:@"sftp"];
	if (!sftpBinaryPath)
	{
		NSLog(@"Could Not Find SFTP Binary Path");
		return;
	}
	
	//Construct the initial argument
	NSArray *passedInArguments = [arguments copy];
	NSArray *commandArguments = [NSArray arrayWithObject:sftpBinaryPath];
	commandArguments = [commandArguments arrayByAddingObjectsFromArray:passedInArguments];
	char **executableArguments;
	[commandArguments createArgv:&executableArguments];
	[passedInArguments release];
	
	connecting = YES;	
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"sftp launch path is %s.\n", executableArguments[0]]];
	
	char teletypewriterName[MAXPATHLEN];
	struct winsize windowSize = {24, 512, 0, 0};
	sftppid = forkpty(&master, teletypewriterName, nil, &windowSize);
	switch (sftppid)
	{
		case 0:
			//SFTP could not be launched
			execve(executableArguments[0], executableArguments, environ);			
			NSLog(@"Could not launch SFTP:%s", strerror(errno));
			_exit(2);
			
		case -1:
			//Error with forkpty()
			NSLog(@"forkpty error:%s", strerror(errno));
			exit(2);
			
		default:
			break;
	}
	[sftpWrapperConnection setMasterProxy:master];
	
	//Ensure the Master doesn't block
	if (fcntl(master, F_SETFL, O_NONBLOCK) < 0)
		NSLog(@"fcntl non-block instruction failed with error:%s", strerror(errno));
	
	//Open the stream
	FILE *masterFileStream = fdopen(master, "r+");
	if (!masterFileStream)
	{
		//Failed to open stream using fdopen
		NSLog(@"Failed to open file stream using fdopen:%s", strerror(errno));
		return;
	}

	//Associate our new file stream
	setvbuf(masterFileStream, nil, _IONBF, 0);
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"Slave terminal device is %s.\n", teletypewriterName]];
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"Master Device is %d.\n", master]];
	
	fd_set readMask;
	char serverResponseBuffer[MAXPATHLEN *2];
	BOOL hasValidPassword = NO;
	BOOL passwordWasSent = NO;
	BOOL rootDirectoryWasSet = NO;
	BOOL wasChanging = NO;
	BOOL wasListing = NO;
	BOOL atSFTPPrompt = NO;
	while (1)
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if (cancelflag)
		{
			fclose(masterFileStream);
			memset(serverResponseBuffer, '\0', strlen(serverResponseBuffer));
			[pool release];
			pool = nil;
			break;
		}		
		
		FD_ZERO(&readMask);
		FD_SET(master, &readMask);
		
		switch(select(master+1, &readMask, nil, nil, nil))
		{
			case -1:
				//Error
				NSLog(@"Select Error:%s", strerror(errno));
				break;
				
			case 0:
				//This is a timeout
				continue;
				
			default:
				break;
		}

		if (FD_ISSET(master, &readMask) && !fgets((char *)serverResponseBuffer, MAXPATHLEN, masterFileStream))
			break;
		
		if (serverResponseBuffer[0] != '\0')
			[sftpWrapperConnection addStringToTranscript:[NSString stringWithUTF8String:serverResponseBuffer]];
		
		if ([self bufferContainsPasswordPrompt:serverResponseBuffer] && !hasValidPassword && connecting)
		{
			[sftpWrapperConnection requestPasswordWithPrompt:(char *)serverResponseBuffer];
			passwordWasSent = YES;
		}
		else if ([self buffer:serverResponseBuffer containsString:"sftp> "])
		{
			//We are waiting at the SFTP Prompt.
			atSFTPPrompt = YES;
			if (!connected)
			{
				passwordWasSent = YES;
				hasValidPassword = YES;
				connecting = NO;
				connected = YES;
				[sftpWrapperConnection didConnect];
			}
			else if (!rootDirectoryWasSet)
			{
				rootDirectoryWasSet = YES;
				[sftpWrapperConnection didSetRootDirectory];
			}
			else if (wasChanging)
			{
				[sftpWrapperConnection directoryContents];
				wasChanging = NO;
			}
			else if (wasListing)
			{
				wasListing = NO;
			}
			[sftpWrapperConnection finishedCommand];
		}
		else
		{
			atSFTPPrompt = NO;
			if (strncmp((char *)serverResponseBuffer, "Permission denied, ", strlen("Permission denied, ")) == 0)
			{
				[sftpWrapperConnection passwordErrorOccurred];
				[self forceDisconnect];
			}
			else if ([self bufferContainsError:serverResponseBuffer])
			{
				[sftpWrapperConnection receivedErrorInServerResponse:[NSString stringWithUTF8String:serverResponseBuffer]];
			}
			else if ([sftpWrapperConnection numberOfTransfers] > 0 || cancelflag)
			{
				if ([sftpWrapperConnection numberOfUploads] > 0)
				{
					NSString *localPath = [[sftpWrapperConnection currentUpload] localPath];
					if ([self buffer:serverResponseBuffer containsString:"%"] && [self buffer:serverResponseBuffer containsString:(char *)[localPath UTF8String]])
					{
						[self parseTransferProgressString:(char *)serverResponseBuffer isUploading:YES forWrapperConnection:sftpWrapperConnection];
					}
				}
				else if ([sftpWrapperConnection numberOfDownloads] > 0)
				{
					NSString *remotePath = [[sftpWrapperConnection currentDownload] remotePath];
					if ([self buffer:serverResponseBuffer containsString:"%"] && [self buffer:serverResponseBuffer containsString:(char *)[remotePath UTF8String]])
					{
						[self parseTransferProgressString:(char *)serverResponseBuffer isUploading:NO forWrapperConnection:sftpWrapperConnection];
					}
				}
			}
			else if ([self buffer:serverResponseBuffer containsString:"passphrase for key"] && !cancelflag)
 			{
				[sftpWrapperConnection passphraseRequested:[NSString stringWithUTF8String:(void *)serverResponseBuffer]];
				passwordWasSent = YES;
			}
			else if ([self buffer:serverResponseBuffer containsString:"Changing owner on"] || [self buffer:serverResponseBuffer containsString:"Changing group on"] || [self buffer:serverResponseBuffer containsString:"Changing mode on"])
			{
				wasChanging = YES;
				if ([self buffer:serverResponseBuffer containsString:"Couldn't "])
				{
					[sftpWrapperConnection receivedErrorInServerResponse:[NSString stringWithUTF8String:serverResponseBuffer]];
				}
			}
			else if ([self unknownHostKeyPromptInBuffer:serverResponseBuffer])
			{
				NSString *key = @"";
				char buf[MAXPATHLEN * 2];
				if (fgets(buf, MAXPATHLEN * 2, masterFileStream) == NULL)
					NSLog(@"fgets:%s\n", strerror(errno));
				else if ((key = [NSString stringWithUTF8String:buf]) == nil)
					key = @"";			
				
				NSMutableDictionary *hostInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
												 [NSString stringWithUTF8String:serverResponseBuffer], @"msg", 
												 key, @"key", nil];
				
				[sftpWrapperConnection getContinueQueryForUnknownHost:hostInfo];
			}
		}
		if ([self buffer:serverResponseBuffer containsString:"Remote working"])
		{
			char *bufferDump = strdup((char *)serverResponseBuffer);
			char *newline = strrchr(bufferDump, '\r');
			if (newline)
			{
				*newline = '\0';
			}
			char *path = strchr(bufferDump, '/');
			NSString *remotePath = [NSString stringWithBytesOfUnknownEncoding:path length:strlen(path)];
			[sftpWrapperConnection setCurrentDirectory:remotePath];
			free(bufferDump);
		}		
		if ([self bufferContainsDirectoryListing:serverResponseBuffer])
		{
			wasListing = YES;
			[self collectListingFromMaster:master fileStream:masterFileStream forWrapperConnection:sftpWrapperConnection];
			memset(serverResponseBuffer, '\0', strlen(serverResponseBuffer));
			[sftpWrapperConnection didReceiveDirectoryContents:directoryContents];
		}
		
		if (serverResponseBuffer[0] != '\0')
		{
			memset(serverResponseBuffer, '\0', strlen(serverResponseBuffer));
		}
		
		[pool release];
		pool = nil;
	}
	cancelflag = NO;
	int status;
	sftppid = wait(&status);
	free(executableArguments);
	connected = NO;
	masterFileStream = nil;
	master = 0;
	(void)close(master);
	
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithUTF8String:serverResponseBuffer]];
	[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"\nsftp task with pid %d ended.\n", sftppid]];
	sftppid = 0;
	[sftpWrapperConnection didDisconnect];
	if (WIFEXITED(status))
		[sftpWrapperConnection addStringToTranscript:@"Normal exit\n"];
	else if (WIFSIGNALED(status))
	{
		[sftpWrapperConnection addStringToTranscript:@"WIFSIGNALED:"];
		[sftpWrapperConnection addStringToTranscript:[NSString stringWithFormat:@"signal = %d\n", status]];
	}
	else if (WIFSTOPPED(status))
		[sftpWrapperConnection addStringToTranscript:@"WIFSTOPPED\n"];
}
@end

//
//  CKConnectionClient.m
//  Connection
//
//  Created by Mike on 15/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionClient.h"

#import "CKAbstractConnection.h"
#import "CKFTPConnection.h"
#import "RunLoopForwarder.h"
#import "NSURL+Connection.h"
#import "CKSFTPConnection.h"

@implementation CKConnectionClient

- (id)initWithConnection:(CKAbstractConnection *)connection
{
    [super init];
    
    _connection = connection;   // Weak ref
    
    _forwarder = [[RunLoopForwarder alloc] init];
    [_forwarder setUseMainThread:YES];
    [_forwarder setReturnValueDelegate:self];
    
    return self;
}

- (CKAbstractConnection *)connection { return _connection; }

- (void)dealloc
{
    [_forwarder release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Delegate

- (void)setDelegate:(id)del
{
	[_forwarder setDelegate:del];
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	_flags.permissions						= [del respondsToSelector:@selector(connection:didSetPermissionsForFile:error:)];
	_flags.cancel							= [del respondsToSelector:@selector(connectionDidCancelTransfer:)];
	_flags.didCancel						= [del respondsToSelector:@selector(connection:didCancelTransfer:)];
	_flags.openAtPath						= [del respondsToSelector:@selector(connection:didOpenAtPath:error:)];
	_flags.changeDirectory					= [del respondsToSelector:@selector(connection:didChangeToDirectory:error:)];
	_flags.createDirectory					= [del respondsToSelector:@selector(connection:didCreateDirectory:error:)];
	_flags.deleteDirectory					= [del respondsToSelector:@selector(connection:didDeleteDirectory:error:)];
	_flags.deleteDirectoryInAncestor		= [del respondsToSelector:@selector(connection:didDeleteDirectory:inAncestorDirectory:error:)];
	_flags.deleteFileInAncestor				= [del respondsToSelector:@selector(connection:didDeleteFile:inAncestorDirectory:error:)];
	_flags.discoverFilesToDeleteInAncestor	= [del respondsToSelector:@selector(connection:didDiscoverFilesToDelete:inAncestorDirectory:)];
	_flags.discoverFilesToDeleteInDirectory = [del respondsToSelector:@selector(connection:didDiscoverFilesToDelete:inDirectory:)];
	_flags.deleteFile						= [del respondsToSelector:@selector(connection:didDeleteFile:error:)];
	_flags.didBeginUpload					= [del respondsToSelector:@selector(connection:uploadDidBegin:)];
	_flags.didConnect						= [del respondsToSelector:@selector(connection:didConnectToHost:error:)];
	_flags.didDisconnect					= [del respondsToSelector:@selector(connection:didDisconnectFromHost:)];
	_flags.directoryContents				= [del respondsToSelector:@selector(connection:didReceiveContents:ofDirectory:error:)];
	_flags.didBeginDownload					= [del respondsToSelector:@selector(connection:downloadDidBegin:)];
	_flags.downloadFinished					= [del respondsToSelector:@selector(connection:downloadDidFinish:error:)];
	_flags.downloadPercent					= [del respondsToSelector:@selector(connection:download:progressedTo:)];
	_flags.downloadProgressed				= [del respondsToSelector:@selector(connection:download:receivedDataOfLength:)];
	_flags.error							= [del respondsToSelector:@selector(connection:didReceiveError:)];
	_flags.rename							= [del respondsToSelector:@selector(connection:didRename:to:error:)];
	_flags.uploadFinished					= [del respondsToSelector:@selector(connection:uploadDidFinish:error:)];
	_flags.uploadPercent					= [del respondsToSelector:@selector(connection:upload:progressedTo:)];
	_flags.uploadProgressed					= [del respondsToSelector:@selector(connection:upload:sentDataOfLength:)];
	_flags.directoryContentsStreamed		= [del respondsToSelector:@selector(connection:didReceiveContents:ofDirectory:moreComing:)];
	_flags.fileCheck						= [del respondsToSelector:@selector(connection:checkedExistenceOfPath:pathExists:error:)];
	_flags.authorizeConnection				= [del respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)];
    _flags.cancelAuthorization              = [del respondsToSelector:@selector(connection:didCancelAuthenticationChallenge:)];
	_flags.passphrase						= [del respondsToSelector:@selector(connection:passphraseForHost:username:publicKeyPath:)];
	_flags.transcript						= [del respondsToSelector:@selector(connection:appendString:toTranscript:)];
}

#pragma mark -
#pragma mark General

- (void)connectionDidConnectToHost:(NSString *)host error:(NSError *)error
{
    if (_flags.didConnect)
    {
        [_forwarder connection:[self connection] didConnectToHost:host error:error];
    }
}

- (void)connectionDidDisconnectFromHost:(NSString *)host
{
    if (_flags.didDisconnect)
    {
        [_forwarder connection:[self connection] didDisconnectFromHost:host];
    }
}

- (void)connectionDidReceiveError:(NSError *)error
{
    if (_flags.error)
    {
        [_forwarder connection:[self connection] didReceiveError:error];
    }
}

#pragma mark -
#pragma mark Authentication
- (NSString *)passphraseForHost:(NSString *)host username:(NSString *)username publicKeyPath:(NSString *)publicKeyPath
{
    NSString *result = nil;
    
    if (_flags.passphrase)
    {
        result = [_forwarder connection:[self connection] passphraseForHost:host username:username publicKeyPath:publicKeyPath];
    }
    
    return result;
}

- (NSString *)accountForUsername:(NSString *)username
{
    NSString *result = nil;
    
    if ([[self connection] delegate] && [[[self connection] delegate] respondsToSelector:@selector(connection:needsAccountForUsername:)])
    {
        result = [_forwarder connection:[self connection] needsAccountForUsername:username];
    }
    
    return result;
}

#pragma mark -
#pragma mark Transcript

/*	Convenience method for sending a string to the delegate for appending to the transcript
 */
- (void)appendLine:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	if (![string hasSuffix:@"\n"])
		string = [string stringByAppendingString:@"\n"];
	
	[self appendString:string toTranscript:transcript];
}

- (void)appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	if (_flags.transcript)
	{
		[_forwarder connection:[self connection] appendString:string toTranscript:transcript];
	}
}

- (void)appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...;
{
	va_list arguments;
	va_start(arguments, transcript);
	NSString *string = [[NSString alloc] initWithFormat:formatString arguments:arguments];
	va_end(arguments);
	
	[self appendLine:string toTranscript:transcript];
	[string release];
}

#pragma mark -
#pragma mark Other

- (void)connectionDidOpenAtPath:(NSString *)dirPath error:(NSError *)error
{
	if (_flags.openAtPath)
		[_forwarder connection:[self connection] didOpenAtPath:dirPath error:error];
}

- (void)connectionDidCreateDirectory:(NSString *)dirPath error:(NSError *)error
{
    if (_flags.createDirectory)
    {
        [_forwarder connection:[self connection] didCreateDirectory:dirPath error:error];
    }
}

- (void)connectionDidDeleteDirectory:(NSString *)dirPath error:(NSError *)error
{
    if (_flags.deleteDirectory)
    {
        [_forwarder connection:[self connection] didDeleteDirectory:dirPath error:error];
    }
}

- (void)connectionDidDeleteFile:(NSString *)path error:(NSError *)error
{
    if (_flags.deleteFile)
    {
        [_forwarder connection:[self connection] didDeleteFile:path error:error];
    }
}

- (void)connectionDidDiscoverFilesToDelete:(NSArray *)contents inAncestorDirectory:(NSString *)ancestorDirPath
{
    if (_flags.discoverFilesToDeleteInAncestor)
    {
        [_forwarder connection:[self connection] didDiscoverFilesToDelete:contents inAncestorDirectory:ancestorDirPath];
    }
}

- (void)connectionDidDiscoverFilesToDelete:(NSArray *)contents inDirectory:(NSString *)dirPath
{
    if (_flags.discoverFilesToDeleteInDirectory)
    {
        [_forwarder connection:[self connection] didDiscoverFilesToDelete:contents inDirectory:dirPath];
    }
}

- (void)connectionDidDeleteDirectory:(NSString *)dirPath inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error
{
    if (_flags.deleteDirectoryInAncestor)
    {
        [_forwarder connection:[self connection] didDeleteDirectory:dirPath inAncestorDirectory:ancestorDirPath error:error];
    }
}

- (void)connectionDidDeleteFile:(NSString *)path inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error
{
    if (_flags.deleteFileInAncestor)
    {
        [_forwarder connection:[self connection] didDeleteFile:path inAncestorDirectory:ancestorDirPath error:error];
    }
}


- (void)connectionDidChangeToDirectory:(NSString *)dirPath error:(NSError *)error
{
    if (_flags.changeDirectory)
    {
        [_forwarder connection:[self connection] didChangeToDirectory:dirPath error:error];
    }
}

- (void)connectionDidReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error
{
    if (_flags.directoryContents)
    {
        [_forwarder connection:[self connection] didReceiveContents:contents ofDirectory:dirPath error:error];
    }
}

- (void)connectionDidRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error
{
    if (_flags.rename)
    {
        [_forwarder connection:[self connection] didRename:fromPath to:toPath error:error];
    }
}

- (void)connectionDidSetPermissionsForFile:(NSString *)path error:(NSError *)error
{
    if (_flags.permissions)
    {
        [_forwarder connection:[self connection] didSetPermissionsForFile:path error:error];
    }
}


- (void)download:(NSString *)path didProgressToPercent:(NSNumber *)percent
{
    if (_flags.downloadPercent)
    {
        [_forwarder connection:[self connection] download:path progressedTo:percent];
    }
}

- (void)download:(NSString *)path didReceiveDataOfLength:(unsigned long long)length
{
    if (_flags.downloadProgressed)
    {
        [_forwarder connection:[self connection] download:path receivedDataOfLength:length];
    }
}

- (void)downloadDidBegin:(NSString *)remotePath
{
    if (_flags.didBeginDownload)
    {
        [_forwarder connection:[self connection] downloadDidBegin:remotePath];
    }
}

- (void)downloadDidFinish:(NSString *)remotePath error:(NSError *)error
{
    if (_flags.downloadFinished)
    {
        [_forwarder connection:[self connection] downloadDidFinish:remotePath error:error];
    }
}


- (void)upload:(NSString *)remotePath didProgressToPercent:(NSNumber *)percent
{
    if (_flags.uploadPercent)
    {
        [_forwarder connection:[self connection] upload:remotePath progressedTo:percent];
    }
}

- (void)upload:(NSString *)remotePath didSendDataOfLength:(unsigned long long)length
{
    if (_flags.uploadProgressed)
    {
        [_forwarder connection:[self connection] upload:remotePath sentDataOfLength:length];
    }
}

- (void)uploadDidBegin:(NSString *)remotePath
{
    if (_flags.didBeginUpload)
    {
        [_forwarder connection:[self connection] uploadDidBegin:remotePath];
    }
}

- (void)uploadDidFinish:(NSString *)remotePath error:(NSError *)error
{
    if (_flags.uploadFinished)
    {
        [_forwarder connection:[self connection] uploadDidFinish:remotePath error:error];
    }
}


- (void)connectionDidCancelTransfer:(NSString *)remotePath
{
    if (_flags.didCancel)
    {
        [_forwarder connection:[self connection] didCancelTransfer:remotePath];
    }
}


- (void)connectionDidCheckExistenceOfPath:(NSString *)path pathExists:(BOOL)exists error:(NSError *)error
{
    if (_flags.fileCheck)
    {
        [_forwarder connection:[self connection] checkedExistenceOfPath:path pathExists:exists error:error];
    }
}


@end


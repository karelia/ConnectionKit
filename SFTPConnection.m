/*
 Copyright (c) 2005, Greg Hulands <ghulands@framedphotographics.com>
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

#import "SFTPConnection.h"
#import "SSHPassphrase.h"
#import "RunLoopForwarder.h"
#import <dirent.h>
#import <sys/types.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import "NSString+Connection.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"

NSString *SFTPException = @"SFTPException";
NSString *SFTPErrorDomain = @"SFTPErrorDomain";

NSString *SFTPTemporaryDataUploadFileKey = @"SFTPTemporaryDataUploadFileKey";
NSString *SFTPRenameFromKey = @"from";
NSString *SFTPRenameToKey = @"to";
NSString *SFTPTransferSizeKey = @"size";

const unsigned int kSFTPBufferSize = 32768;

@interface SFTPConnection (Private)

+ (NSString *)escapedPathStringWithString:(NSString *)str;
- (void)sendCommand:(id)cmd;
- (NSString *)error;

@end


static int ssh_write(uint8_t *buffer, int length, LIBSSH2_SESSION *session, void *info);
static int ssh_read(uint8_t *buffer, int length, LIBSSH2_SESSION *session, void *info);

@implementation SFTPConnection

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"22", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"sftp://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	NSDictionary *url2 = [NSDictionary dictionaryWithObjectsAndKeys:@"ssh://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[SFTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, url2, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"SFTP";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	return [[[SFTPConnection alloc] initWithHost:host
										   port:port
									   username:username
									   password:password
										   error:error] autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (!username || [username length] == 0)
	{
		if (error)
		{
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain
											   code:ConnectionNoUsernameOrPassword
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Username is required for SFTP connections", @"No username or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
	}
  //enforce default port for sftp
  //
  if (![port length])
    port = @"22";
  
	if (self = [super initWithHost:host port:port username:username password:password error:error]) {
		
	}
	return self;
}

- (void)dealloc
{
	
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"sftp";
}

#pragma mark -
#pragma mark Connection Overrides

- (void)runloopForwarder:(RunLoopForwarder *)rlw returnedValue:(void *)value
{
	BOOL authorizeConnection = (BOOL)*((BOOL *)value);
	mySFTPFlags.authorized = authorizeConnection;
}

- (void)keychainFingerPrint
{
	NSDictionary *map = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".ssh_hosts"]];
	[myKeychainFingerPrint autorelease];
	myKeychainFingerPrint = [[map objectForKey:[self host]] retain];
}

- (void)setFingerprint:(NSString *)fp
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh_hosts"];
	NSMutableDictionary *map = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	if (!map) map = [NSMutableDictionary dictionary];
	
	[map setObject:fp forKey:[self host]];
	[map writeToFile:file atomically:YES];
}

- (BOOL)checkFingerPrint:(NSString *)fp
{
	[self keychainFingerPrint];
	BOOL needsAuthorization = YES;
	
	if ([fp length] > 0)
	{
		if ([myKeychainFingerPrint isEqualToString:fp])
		{
			needsAuthorization = NO;
		}
		else
		{
			if (_flags.authorizeConnection)
			{
				NSString *localised = [NSString stringWithFormat:LocalizedStringInThisBundle(@"%@'s fingerprint does not match the one on record. If the server has changed its key, then this is to be expected. If not then you should check with the system administrator before proceeding.\nThe new fingerprint is %@.\nDo you wish to connect to the server?", @"ssh host key changed"), [self host], fp];
				mySFTPFlags.authorized = NO;
				[_forwarder connection:self authorizeConnectionToHost:[self host] message:localised];
				if (mySFTPFlags.authorized)
				{
					//add the fingerprint to the keychain item
					[self setFingerprint:fp];
					return YES;
				}
				else
				{
					return NO;
				}
			}
			return NO;
		}
	}
	
	if (needsAuthorization)
	{
		if (_flags.authorizeConnection)
		{
			mySFTPFlags.authorized = NO;
			NSString *localised = [NSString stringWithFormat:LocalizedStringInThisBundle(@"This is the first time connecting to %@. It has a fingerprint of \n%@. Do you wish to connect?", @"ssh authorise remote host fingerprint"), [self host], fp];
			[_forwarder connection:self authorizeConnectionToHost:[self host] message:localised];
			if (mySFTPFlags.authorized)
			{
				return YES;
			}
			else
			{
				return NO;
			}
		}
		else
		{
			NSLog(@"delegate does not implement connection:authorizeConnectionToHost:");
			return NO;
		}
	}
	else 
	{
		return YES;
	}
}

- (void)mainThreadPassphrase:(NSString *)publicKey
{
	SSHPassphrase *pass = [[SSHPassphrase alloc] init];
	NSString *passphrase = [pass passphraseForPublicKey:publicKey account:[self username]];
	[myKeychainFingerPrint autorelease];
	myKeychainFingerPrint = [passphrase copy];		// will be nil if passphrase not given (cancel button)
	[pass release];
}

- (void)negotiateSSH
{	
	if (libssh2_session_startup(mySession, [self socket])) 
	{
		NSLog(@"%@: %@", NSStringFromSelector(_cmd), [self error]);
		if (_flags.error)
		{
			NSError *error = [NSError errorWithDomain: SFTPErrorDomain
												 code: libssh2_session_last_error(mySession,nil,nil,0)
											 userInfo: [NSDictionary dictionaryWithObject:[self error] forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError: error];
		}
	}
	const char *fingerprint = libssh2_hostkey_hash(mySession, LIBSSH2_HOSTKEY_HASH_MD5);
	NSMutableString *fp = [NSMutableString stringWithString:@""];
	int i;
	for(i = 0; i < 16; i++) {
		[fp appendFormat:@"%02X", (unsigned char)fingerprint[i]];
	}
	if (![self checkFingerPrint:fp])
	{
		[self threadedForceDisconnect];
		return;
	}
	
	if ([self password] && [[self password] length] > 0) {
		/* We could authenticate via password */
		if (libssh2_userauth_password(mySession, [[self username] UTF8String], [[self password] UTF8String])) {
			if (_flags.badPassword)
			{
				[_forwarder connectionDidSendBadPassword:self];
			}
			[self threadedForceDisconnect];
			return;
		}
	} 
	else 
	{
		// Or by public key 
		NSString *publicKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"SSHPublicKey"];
		if (!publicKey)
		{
			publicKey = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh/id_dsa.pub"];
		}
		NSFileManager *fm = [NSFileManager defaultManager];
		if (![fm fileExistsAtPath:publicKey])
		{
			publicKey = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh/id_rsa.pub"];
		}
		NSString *privateKey = [publicKey stringByDeletingPathExtension];
		
		
		if (![fm fileExistsAtPath:publicKey])
		{
			if (_flags.error)
			{
				NSString *localised = [NSString stringWithFormat:LocalizedStringInThisBundle(@"Failed to find public key in %@. If you have a custom named key, please set the User Default key SSHPublicKey.", @"failed to find the id_dsa.pub"), publicKey];
				NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorAuthentication userInfo:[NSDictionary dictionaryWithObject:localised forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:err];
			}
			[self threadedForceDisconnect];
			return;
		}
		//need to see if the password is stored in the keychain
		[self performSelectorOnMainThread:@selector(mainThreadPassphrase:) withObject:publicKey waitUntilDone:YES];
		if (!myKeychainFingerPrint)
		{
			[self threadedForceDisconnect];
			return;		// no fingerprint retrieved -- cancel connection.
			
		}
		if (libssh2_userauth_publickey_fromfile(mySession, [[self username] UTF8String], [publicKey UTF8String], [privateKey UTF8String], [myKeychainFingerPrint UTF8String]))
		{
			if (_flags.error)
			{
				NSString *localised = LocalizedStringInThisBundle(@"Authentication by Public Key Failed", @"failed pk authentication for ssh");
				NSString *error = [self error];
				NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorAuthentication userInfo:[NSDictionary dictionaryWithObjectsAndKeys:localised, NSLocalizedDescriptionKey, error, NSUnderlyingErrorKey, nil]];
				[_forwarder connection:self didReceiveError:err];
			}
			[self threadedForceDisconnect];
			return;
		}
	}
	
	if (!mySession || !libssh2_userauth_authenticated(mySession))
	{
		if (_flags.error)
		{
			NSString *localised = LocalizedStringInThisBundle(@"Authentication Failed. Do you have permission to access this server via SFTP?", @"failed authentication for ssh");
			NSString *error = [self error];
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorAuthentication userInfo:[NSDictionary dictionaryWithObjectsAndKeys:localised, NSLocalizedDescriptionKey, error, NSUnderlyingErrorKey, nil]];
			[_forwarder connection:self didReceiveError:err];
		}
		[self threadedForceDisconnect];
		return;
	}
	
	// motd
	LIBSSH2_CHANNEL *motd = libssh2_channel_open_session(mySession);
	char motdmsg[1024];
	int ret = libssh2_channel_read(motd, motdmsg, 1024);
	
	while (ret > 0)
	{
		if ([self transcript])
		{
			[self appendToTranscript:[NSAttributedString attributedStringWithString:[NSString stringWithData:[NSData dataWithBytes:motdmsg length:ret] encoding:NSUTF8StringEncoding] 
																		 attributes:[AbstractConnection dataAttributes]]];
		}
	}
	ret = libssh2_channel_close(motd);

	//find out the home directory
	LIBSSH2_CHANNEL *pwd = libssh2_channel_open_session(mySession);
	ret = libssh2_channel_exec(pwd, "/bin/pwd");
	char dir[1024];
	[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]; //give it time to have something to read
	ret = libssh2_channel_read(pwd, dir, 1024);
	if (dir[ret-1] == '\n') ret--;
	_currentDir = [[NSString alloc] initWithCString:dir length:ret];
	ret = libssh2_channel_close(pwd);
	
	mySFTPChannel = libssh2_sftp_init(mySession);
	if (mySFTPChannel == NULL)
	{
		if (_flags.error)
		{
			NSString *localised = LocalizedStringInThisBundle(@"Failed to initialize SFTP Subsystem. Do you have permission to access this server via SFTP?", @"failed authentication for ssh");
			NSString *error = [self error];
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorAuthentication userInfo:[NSDictionary dictionaryWithObjectsAndKeys:localised, NSLocalizedDescriptionKey, error, NSUnderlyingErrorKey, nil]];
			[_forwarder connection:self didReceiveError:err];
		}
		[self threadedForceDisconnect];
	}
	
	[self setState:ConnectionIdleState];
	if (_flags.didConnect)
	{
		[_forwarder connection:self didConnectToHost:[self host]];
	}
}

- (void)sendStreamDidOpen
{
	if ([self sendStreamOpen] && [self receiveStreamOpen])
	{
		[self performSelector:@selector(negotiateSSH) withObject:nil afterDelay:0.0];
	}
}

- (void)receiveStreamDidOpen
{
	if ([self sendStreamOpen] && [self receiveStreamOpen])
	{
		[self performSelector:@selector(negotiateSSH) withObject:nil afterDelay:0.0];
	}
}

- (void)threadedConnect
{	
	mySession = libssh2_session_init();
	libssh2_session_set_user_info(mySession,self);
	libssh2_session_set_read(mySession,ssh_read);
	libssh2_session_set_write(mySession,ssh_write);
	
	[super threadedConnect];
  _flags.isConnected = YES;
}

- (void)threadedDisconnect
{
	int ret = libssh2_sftp_shutdown(mySFTPChannel); mySFTPChannel = NULL;
	ret = libssh2_session_disconnect(mySession, "bye bye");
	libssh2_session_free(mySession); mySession = NULL;
	[super threadedDisconnect];
}

- (void)threadedForceDisconnect
{
	ConnectionCommand *cmd = [ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDisconnect) target:self arguments:[NSArray array]]
											 awaitState:ConnectionIdleState
											  sentState:ConnectionSentDisconnectState
											  dependant:nil
											   userInfo:nil];
	[self pushCommandOnCommandQueue:cmd];
}

#pragma mark -
#pragma mark Stream Overrides

- (BOOL)shouldChunkData
{
	return NO;
}

#pragma mark -
#pragma mark State Machine

- (NSString *)sftpError
{
	unsigned long err = libssh2_sftp_last_error(mySFTPChannel);
	switch (err)
	{
		case LIBSSH2_FX_OK: return LocalizedStringInThisBundle(@"OK", @"sftp last error");
		case LIBSSH2_FX_EOF: return LocalizedStringInThisBundle(@"End of File", @"sftp last error");
		case LIBSSH2_FX_NO_SUCH_FILE: return LocalizedStringInThisBundle(@"No such file", @"sftp last error");
		case LIBSSH2_FX_PERMISSION_DENIED: return LocalizedStringInThisBundle(@"Permission Denied", @"sftp last error");
		case LIBSSH2_FX_FAILURE: return LocalizedStringInThisBundle(@"Failure", @"sftp last error");
		case LIBSSH2_FX_BAD_MESSAGE: return LocalizedStringInThisBundle(@"Bad Message", @"sftp last error");
		case LIBSSH2_FX_NO_CONNECTION: return LocalizedStringInThisBundle(@"No Connection", @"sftp last error");
		case LIBSSH2_FX_CONNECTION_LOST: return LocalizedStringInThisBundle(@"Connection Lost", @"sftp last error");
		case LIBSSH2_FX_OP_UNSUPPORTED: return LocalizedStringInThisBundle(@"Operation Unsupported", @"sftp last error");
		case LIBSSH2_FX_INVALID_HANDLE: return LocalizedStringInThisBundle(@"Invalid Handle", @"sftp last error");
		case LIBSSH2_FX_NO_SUCH_PATH: return LocalizedStringInThisBundle(@"No such path", @"sftp last error");
		case LIBSSH2_FX_FILE_ALREADY_EXISTS: return LocalizedStringInThisBundle(@"File already exists", @"sftp last error");
		case LIBSSH2_FX_WRITE_PROTECT: return LocalizedStringInThisBundle(@"Write Protected", @"sftp last error");
		case LIBSSH2_FX_NO_MEDIA: return LocalizedStringInThisBundle(@"No Media", @"sftp last error");
		case LIBSSH2_FX_NO_SPACE_ON_FILESYSTEM: return LocalizedStringInThisBundle(@"No space left on remote machine", @"sftp last error");
		case LIBSSH2_FX_QUOTA_EXCEEDED: return LocalizedStringInThisBundle(@"Quota exceeded", @"sftp last error");
		case LIBSSH2_FX_UNKNOWN_PRINCIPLE: return LocalizedStringInThisBundle(@"Unknown Principle", @"sftp last error");
		case LIBSSH2_FX_LOCK_CONFlICT: return LocalizedStringInThisBundle(@"Lock Conflict", @"sftp last error");
		case LIBSSH2_FX_DIR_NOT_EMPTY: return LocalizedStringInThisBundle(@"Directory not empty", @"sftp last error");
		case LIBSSH2_FX_NOT_A_DIRECTORY: return LocalizedStringInThisBundle(@"Not a directory", @"sftp last error");
		case LIBSSH2_FX_INVALID_FILENAME: return LocalizedStringInThisBundle(@"Invalid filename", @"sftp last error");
		case LIBSSH2_FX_LINK_LOOP: return LocalizedStringInThisBundle(@"Link Loop", @"sftp last error");
		case LIBSSH2_ERROR_REQUEST_DENIED: return LocalizedStringInThisBundle(@"Request Denied", @"sftp last error");
		case LIBSSH2_ERROR_METHOD_NOT_SUPPORTED: return LocalizedStringInThisBundle(@"Method not Supported", @"sftp last error");
		case LIBSSH2_ERROR_INVAL: return LocalizedStringInThisBundle(@"Error INVAL", @"sftp last error");
	}
	return @"";
}

- (NSString *)error
{
	char *errmsg;
	int len;
	int err = libssh2_session_last_error(mySession,&errmsg,&len,0);
	if (err == LIBSSH2_ERROR_SFTP_PROTOCOL)
	{
		return [self sftpError];
	}
	return [NSString stringWithCString:errmsg length:len];
}

- (void)sendCommand:(id)cmd
{
	if ([cmd isKindOfClass:[NSInvocation class]])
	{
		KTLog(StateMachineDomain, KTLogDebug, @"Invoking command %@", NSStringFromSelector([cmd selector]));
		[cmd invoke];
	}
}

#pragma mark -
#pragma mark Connection Commands 

- (void)threadedChangeToDirectory:(NSString *)dirPath
{
	LIBSSH2_SFTP_HANDLE *dir = libssh2_sftp_opendir(mySFTPChannel, [dirPath UTF8String]);
	
	if (dir == NULL)
	{
		if (_flags.error)
		{
			NSString *localised = [NSString stringWithFormat:LocalizedStringInThisBundle(@"The directory (%@) does not exist", @"sftp bad directory"), dirPath];
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorDirectoryDoesNotExist userInfo:[NSDictionary dictionaryWithObject:localised forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:err];
		}
	}
	else
	{
		[_currentDir autorelease];
		_currentDir = [dirPath copy];
		if (_flags.changeDirectory)
		{
			[_forwarder connection:self didChangeToDirectory:_currentDir];
		}
	}
	if (dir) libssh2_sftp_close_handle(dir);
	[self setState:ConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	ConnectionCommand *cd = [ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedChangeToDirectory:) target:self arguments:[NSArray arrayWithObject:dirPath]]
											awaitState:ConnectionIdleState
											 sentState:ConnectionChangingDirectoryState
											 dependant:nil
											  userInfo:nil];
	[self queueCommand:cd];
}

- (NSString *)currentDirectory
{
	return _currentDir;
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)threadedCreateDirectory:(NSString *)dirPath
{
	if (libssh2_sftp_mkdir(mySFTPChannel, [dirPath UTF8String], 040755))
	{
		if (_flags.error && !_flags.isRecursiveUploading)
		{
			int msglen;
			char *msg;
			int errcode = libssh2_session_last_error(mySession,&msg,&msglen,0);
			NSMutableDictionary *ui = [NSMutableDictionary dictionary];
			[ui setObject:[NSString stringWithCString:msg length:msglen] forKey:NSUnderlyingErrorKey];
			[ui setObject:LocalizedStringInThisBundle(@"Failed to create directory", @"sftp failure to create dir") forKey:NSLocalizedDescriptionKey];
			if (errcode == LIBSSH2_ERROR_SFTP_PROTOCOL)
			{
				[ui setObject:[self sftpError] forKey:NSLocalizedDescriptionKey];
			}
			[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
			[ui setObject:dirPath forKey:ConnectionDirectoryExistsFilenameKey];
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorGeneric userInfo:ui];
			[_forwarder connection:self didReceiveError:err];
		}
	}
	else
	{
		if (_flags.createDirectory)
		{
			[_forwarder connection:self didCreateDirectory:dirPath];
		}
	}
	[self setState:ConnectionIdleState];
}

- (void)createDirectory:(NSString *)dirPath
{
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedCreateDirectory:) target:self arguments:[NSArray arrayWithObject:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionCreateDirectoryState
										dependant:nil
										 userInfo:nil]];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	[self createDirectory:dirPath];
	[self setPermissions:permissions forFile:dirPath];
}

- (void)threadedSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	unsigned long permissions = [perms unsignedLongValue];
	LIBSSH2_SFTP_ATTRIBUTES attribs;
	char *utf8 = (char *)[path UTF8String];
	int ret = libssh2_sftp_stat_ex(mySFTPChannel, utf8, strlen(utf8), 0, &attribs);
	unsigned long newPerms = attribs.permissions | permissions;
	attribs.permissions = newPerms;
	ret = libssh2_sftp_stat_ex(mySFTPChannel, utf8, strlen(utf8), 1, &attribs);
	[self setState:ConnectionIdleState];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	[self queuePermissionChange:path];
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:) target:self arguments:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:permissions], path, nil]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionSettingPermissionsState
										dependant:nil
										 userInfo:nil]];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	[self queueRename:[NSDictionary dictionaryWithObjectsAndKeys:fromPath, SFTPRenameFromKey, toPath, SFTPRenameToKey, nil]];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"rename %@ %@", [SFTPConnection escapedPathStringWithString:fromPath], [SFTPConnection escapedPathStringWithString:toPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingRenameState
										dependant:nil
										 userInfo:nil]];
}

- (void)threadedDeleteFile:(NSString *)path
{
	if (libssh2_sftp_unlink(mySFTPChannel, (char *)[path UTF8String]))
	{
		//report error
	}
	else
	{
		if (_flags.deleteFile)
		{
			[_forwarder connection:self didDeleteFile:path];
		}
	}
	[self setState:ConnectionIdleState];
}

- (void)deleteFile:(NSString *)path
{
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDeleteFile:) target:self arguments:[NSArray arrayWithObject:path]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDeleteFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"need to upate to new sftp library" userInfo:nil];
	[self queueDeletion:dirPath];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"rmdir %@", [SFTPConnection escapedPathStringWithString:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDeleteDirectoryState
										dependant:nil
										 userInfo:nil]];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[[self currentDirectory] stringByAppendingPathComponent: [localPath lastPathComponent]]];
}

- (void)threadedRunloopUploadFile:(NSFileHandle *)file
{
	CKInternalTransferRecord *upload = [self currentUpload];
	NSString *remote = [upload remotePath];
	NSData *data = [file readDataOfLength:kSFTPBufferSize];
	size_t chunksent = libssh2_sftp_write(myTransferHandle,[data bytes],[data length]);
	if (_flags.uploadProgressed)
	{
		[_forwarder connection:self upload:remote sentDataOfLength:chunksent];
	}
	if ([upload delegateRespondsToTransferTransferredData])
	{
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:chunksent];
	}
	if (chunksent != [data length])
	{
//		NSError *error = [NSError errorWithDomain:SFTPErrorDomain
//											 code:SFTPErrorWrite
//										 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Failed to write all data", @"sftp error"), NSLocalizedDescriptionKey, nil]];
//		if (_flags.error)
//		{
//			[_forwarder connection:self didReceiveError:error];
//		}
//		if ([upload delegateRespondsToError])
//		{
//			[[upload delegate] transfer:[upload userInfo] receivedError:error];
//		}
	}
	myBytesTransferred += chunksent;
	int percent = (int)((myBytesTransferred * 100) / myTransferSize);
	if (_flags.uploadPercent)
	{
		[_forwarder connection:self upload:remote progressedTo:[NSNumber numberWithInt:percent]];
	}
	if ([upload delegateRespondsToTransferProgressedTo])
	{
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
	}
	if (myBytesTransferred == myTransferSize)
	{
		[upload retain];
		[self dequeueUpload];
		if (_flags.uploadFinished)
		{
			[_forwarder connection:self uploadDidFinish:remote];
		}
		if ([upload delegateRespondsToTransferDidFinish])
		{
			[[upload delegate] transferDidFinish:[upload userInfo]];
		}
		[upload release];
		libssh2_sftp_close_handle(myTransferHandle); myTransferHandle = NULL;
		[self setState:ConnectionIdleState];
	}
	else 
	{
		[self performSelector:@selector(threadedRunloopUploadFile:) withObject:file afterDelay:0.0];
	}
}

- (void)threadedUploadFile
{
	CKInternalTransferRecord *upload = [self currentUpload];
	NSString *local = [upload localPath];
	NSString *remote = [upload remotePath];
	myTransferSize = [[[upload userInfo] objectForKey:SFTPTransferSizeKey] unsignedLongLongValue];
	myTransferHandle = libssh2_sftp_open(mySFTPChannel, [remote UTF8String], LIBSSH2_FXF_TRUNC | LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT, 0100644);
	myBytesTransferred = 0;
	
	NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:local];
	if (_flags.didBeginUpload)
	{
		[_forwarder connection:self uploadDidBegin:remote];
	}
	if ([upload delegateRespondsToTransferDidBegin])
	{
		[[upload delegate] transferDidBegin:[upload userInfo]];
	}
	[self performSelector:@selector(threadedRunloopUploadFile:) withObject:file afterDelay:0.0];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSDictionary *attribs = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
	CKTransferRecord *upload = [CKTransferRecord recordWithName:remotePath size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue]];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : upload
																		userInfo:upload];
	[upload setUpload:YES];
	[upload setObject:localPath forKey:QueueUploadLocalFileKey];
	[upload setObject:remotePath forKey:QueueUploadRemoteFileKey];
	[upload setObject:[attribs objectForKey:NSFileSize] forKey:SFTPTransferSizeKey];
	[self queueUpload:record];
	
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedUploadFile) target:self arguments:[NSArray array]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionUploadingFileState
										dependant:nil
										 userInfo:nil]];
	
	return upload;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	//we don't support resuming over sftp
	[self uploadFile:localPath];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	//we don't support resuming over sftp
	[self uploadFile:localPath toFile:remotePath];
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	return [self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:delegate];
}

- (void)threadedRunloopUploadData:(NSData *)data
{
	CKInternalTransferRecord *upload = [self currentUpload];
	NSString *remote = [upload remotePath];
	NSRange byteRange = NSMakeRange(myBytesTransferred, kSFTPBufferSize);
	if (NSMaxRange(byteRange) > [data length])
	{
		byteRange.length = myTransferSize - myBytesTransferred;
	}
	NSData *chunk = [data subdataWithRange:byteRange];
	size_t chunksent = libssh2_sftp_write(myTransferHandle,[chunk bytes],[chunk length]);
	if (_flags.uploadProgressed)
	{
		[_forwarder connection:self upload:remote sentDataOfLength:chunksent];
	}
	if ([upload delegateRespondsToTransferTransferredData])
	{
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:chunksent];
	}
	if (chunksent != [data length])
	{
//		NSError *error = [NSError errorWithDomain:SFTPErrorDomain
//											 code:SFTPErrorWrite
//										 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Failed to write all data", @"sftp error"), NSLocalizedDescriptionKey, nil]];
//		if (_flags.error)
//		{
//			[_forwarder connection:self didReceiveError:error];
//		}
//		if ([upload delegateRespondsToError])
//		{
//			[[upload delegate] transfer:[upload userInfo] receivedError:error];
//		}
	}
	myBytesTransferred += chunksent;
	int percent = (int)((myBytesTransferred * 100) / myTransferSize);
	if (_flags.uploadPercent)
	{
		[_forwarder connection:self upload:remote progressedTo:[NSNumber numberWithInt:percent]];
	}
	if ([upload delegateRespondsToTransferProgressedTo])
	{
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
	}
	if (myBytesTransferred == myTransferSize)
	{
		[upload retain];
		[self dequeueUpload];
		if (_flags.uploadFinished)
		{
			[_forwarder connection:self uploadDidFinish:remote];
		}
		if ([upload delegateRespondsToTransferDidFinish])
		{
			[[upload delegate] transferDidFinish:[upload userInfo]];
		}
		[upload release];
		libssh2_sftp_close_handle(myTransferHandle); myTransferHandle = NULL;
		[self setState:ConnectionIdleState];
	}
	else 
	{
		[self performSelector:@selector(threadedRunloopUploadData:) withObject:data afterDelay:0.0];
	}
}

- (void)threadedUploadData
{
	CKInternalTransferRecord *upload = [self currentUpload];
	NSData *data = [[upload userInfo] objectForKey:QueueUploadLocalDataKey];
	NSString *remote = [upload remotePath];
	myTransferSize = [[[upload userInfo] objectForKey:SFTPTransferSizeKey] unsignedLongLongValue];
	myTransferHandle = libssh2_sftp_open(mySFTPChannel, [remote UTF8String], LIBSSH2_FXF_TRUNC | LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT, 0100644);
	myBytesTransferred = 0;
	
	if (_flags.didBeginUpload)
	{
		[_forwarder connection:self uploadDidBegin:remote];
	}
	if ([upload delegateRespondsToTransferDidBegin])
	{
		[[upload delegate] transferDidBegin:[upload userInfo]];
	}
	[self performSelector:@selector(threadedRunloopUploadData:) withObject:data afterDelay:0.0];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	CKTransferRecord *upload = [CKTransferRecord recordWithName:remotePath size:[data length]];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:nil
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : upload
																		userInfo:upload];
	[upload setUpload:YES];
	[upload setObject:data forKey:QueueUploadLocalDataKey];
	[upload setObject:remotePath forKey:QueueUploadRemoteFileKey];
	[upload setObject:[NSNumber numberWithUnsignedInt:[data length]] forKey:SFTPTransferSizeKey];
	[self queueUpload:record];
	
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedUploadData) target:self arguments:[NSArray array]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionUploadingFileState
										dependant:nil
										 userInfo:nil]];
	
	return upload;
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	//we don't support resuming over sftp
	[self uploadFromData:data toFile:remotePath];
}

- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate
{
	return [self uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:delegate];
}

- (void)threadedRunloopDownload:(NSFileHandle *)file
{
	CKInternalTransferRecord *download = [self currentDownload];
	NSString *remote = [download remotePath];
	NSMutableData *data = [NSMutableData dataWithLength:kSFTPBufferSize];
	size_t read = libssh2_sftp_read(myTransferHandle,[data mutableBytes],kSFTPBufferSize);
	
	//if we read less than the size of the buffer we need to write only what was read to the file
	data = (NSMutableData *)[data subdataWithRange: NSMakeRange(0, read)];
  
	if (_flags.downloadProgressed)
	{
		[_forwarder connection:self download:remote receivedDataOfLength:read];
	}
	if ([download delegateRespondsToTransferTransferredData])
	{
		[[download delegate] transfer:[download userInfo] transferredDataOfLength:read];
	}
	[file writeData:data];
	myBytesTransferred += read;
	int percent = (int)((myBytesTransferred * 100) / myTransferSize);
	if (_flags.downloadPercent)
	{
		[_forwarder connection:self download:remote progressedTo:[NSNumber numberWithInt:percent]];
	}
	if ([download delegateRespondsToTransferProgressedTo])
	{
		[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
	}
	
	if (myBytesTransferred == myTransferSize)
	{
		[download retain];
		[self dequeueDownload];
		if (_flags.uploadFinished)
		{
			[_forwarder connection:self downloadDidFinish:remote];
		}
		if ([download delegateRespondsToTransferDidFinish])
		{
			[[download delegate] transferDidFinish:[download userInfo]];
		}
		[download release];
		libssh2_sftp_close_handle(myTransferHandle); myTransferHandle = NULL;
		[self setState:ConnectionIdleState];
	}
	else 
	{
		[self performSelector:@selector(threadedRunloopDownload:) withObject:file afterDelay:0.0];
	}
}

- (void)threadedDownload
{
	CKInternalTransferRecord *download = [self currentDownload];
	NSString *remoteFile = [download remotePath];
	NSString *localFile = [download localPath];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:localFile])
	{
		[fm removeFileAtPath:localFile handler:nil];
	}
	[fm createFileAtPath:localFile contents:[NSData data] attributes:nil];
	NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:localFile];
	myTransferHandle = libssh2_sftp_open(mySFTPChannel, [remoteFile UTF8String], LIBSSH2_FXF_READ, 0);
	LIBSSH2_SFTP_ATTRIBUTES attrs;
	
	if (libssh2_sftp_fstat(myTransferHandle, &attrs))
	{
		//err
	}
	myTransferSize = attrs.filesize;
	myBytesTransferred = 0;
	
	if (_flags.didBeginDownload)
	{
		[_forwarder connection:self downloadDidBegin:remoteFile];
	}
	if ([download delegateRespondsToTransferDidBegin])
	{
		[[download delegate] transferDidBegin:[download userInfo]];
	}
	[self performSelector:@selector(threadedRunloopDownload:) withObject:handle afterDelay:0.0];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{	
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localFile = [NSString stringWithFormat:@"%@/%@", dirPath, remoteFileName];
	if (!flag)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:localFile])
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:FTPDownloadFileExists
												 userInfo:[NSDictionary dictionaryWithObject:@"Local File already exists" forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:error];
			}
		}
	}
	NSMutableDictionary *download = [NSMutableDictionary dictionary];
	[download setObject:remotePath forKey:QueueDownloadRemoteFileKey];
	[download setObject:localFile forKey:QueueDownloadDestinationFileKey];
	[self queueDownload:download];
	
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDownload) target:self arguments:[NSArray array]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDownloadingFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	//we don't support resuming over sftp
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	return [self downloadFile:remotePath toDirectory:dirPath overwrite:YES delegate:delegate];
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	return [self downloadFile:remotePath toDirectory:dirPath overwrite:YES delegate:delegate];
}

- (void)cancelTransfer
{
	
}

- (void)cancelAll
{
	
}

- (void)threadedContentsOfDirectory:(NSString *)directory
{
	char *dirbuf = (char *)malloc(sizeof(char) * kSFTPBufferSize);
	LIBSSH2_SFTP_HANDLE *dir = libssh2_sftp_opendir(mySFTPChannel, [directory UTF8String]);
	
	if (dir == NULL)
	{
		if (_flags.error)
		{
			NSString *localised = [NSString stringWithFormat:LocalizedStringInThisBundle(@"The directory (%@) does not exist", @"sftp bad directory"), directory];
			NSError *err = [NSError errorWithDomain:SFTPErrorDomain code:SFTPErrorDirectoryDoesNotExist userInfo:[NSDictionary dictionaryWithObject:localised forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:err];
		}
	}
	else
	{
		if (_flags.directoryContents)
		{
			LIBSSH2_SFTP_ATTRIBUTES attribs;
			NSMutableArray *contents = [NSMutableArray array];
			int c;
			while ((c = libssh2_sftp_readdir(dir,dirbuf,kSFTPBufferSize,&attribs)) > 0)
			{
				dirbuf[c] = '\0';
				NSMutableDictionary *at = [NSMutableDictionary dictionary];
				NSString *filename = [NSString stringWithUTF8String:dirbuf];
				[at setObject:filename forKey:cxFilenameKey];
				if (attribs.flags & LIBSSH2_SFTP_ATTR_SIZE) 
				{
					[at setObject:[NSNumber numberWithUnsignedLong:attribs.filesize] forKey:NSFileSize];
				}
				if (attribs.flags & LIBSSH2_SFTP_ATTR_UIDGID)
				{
					[at setObject:[NSNumber numberWithUnsignedLong:attribs.gid] forKey:NSFileGroupOwnerAccountID];
					[at setObject:[NSNumber numberWithUnsignedLong:attribs.uid] forKey:NSFileOwnerAccountID];
				}
				if (attribs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS)
				{
					[at setObject:[NSNumber numberWithUnsignedLong:attribs.permissions] forKey:NSFilePosixPermissions];
				}
				if (attribs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME)
				{
					[at setObject:[NSDate dateWithTimeIntervalSince1970:attribs.mtime] forKey:NSFileModificationDate];
				}
				
				if (attribs.permissions & S_IFDIR)
				{
					[at setObject:NSFileTypeDirectory forKey:NSFileType];
				}
				else if (attribs.permissions & S_IFIFO)
				{
					[at setObject:NSFileTypeUnknown forKey:NSFileType];
				}
				else if (attribs.permissions & S_IFCHR)
				{
					[at setObject:NSFileTypeCharacterSpecial forKey:NSFileType];
				}
				else if (attribs.permissions & S_IFBLK)
				{
					[at setObject:NSFileTypeBlockSpecial forKey:NSFileType];
				}
				else if (attribs.permissions & S_IFREG)
				{
					[at setObject:NSFileTypeRegular forKey:NSFileType];
				}
				else if (attribs.permissions & S_IFLNK)
				{
					[at setObject:NSFileTypeSymbolicLink forKey:NSFileType];
					//need to get the target
				}
				else if (attribs.permissions & S_IFSOCK)
				{
					[at setObject:NSFileTypeSocket forKey:NSFileType];
				}
				else 
				{
					[at setObject:NSFileTypeUnknown forKey:NSFileTypeUnknown];
				}

				[contents addObject:at];
			}
			free(dirbuf);
			[self cacheDirectory:directory withContents:contents];
			[_forwarder connection:self didReceiveContents:contents ofDirectory:directory];
		}
	}

	if (dir) libssh2_sftp_close_handle(dir);
	[self setState:ConnectionIdleState];
}

- (void)threadedDirectoryContents
{
	[self threadedContentsOfDirectory:_currentDir];
}

- (void)directoryContents
{
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDirectoryContents) target:self arguments:[NSArray array]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	[self queueCommand:[ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedContentsOfDirectory:) target:self arguments:[NSArray arrayWithObject:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[_forwarder connection:self didReceiveContents:cachedContents ofDirectory:dirPath];
	}
}

+ (NSString *)escapedPathStringWithString:(NSString *)str
{
	if ([str rangeOfString:@" "].location != NSNotFound)
		return [NSString stringWithFormat:@"\"%@\"", str];
	return str;
}
@end


static int ssh_write(uint8_t *buffer, int length, LIBSSH2_SESSION *session, void *info)
{
	SFTPConnection *con = (SFTPConnection *)info;
	NSData *data = [NSData dataWithBytes:buffer length:length];
	[con sendData:data];
	
	return [data length];
}

static int ssh_read(uint8_t *buffer, int length, LIBSSH2_SESSION *session, void *info)
{
	SFTPConnection *con = (SFTPConnection *)info;
	NSData *data;
	int size = [con availableData:&data ofLength:length];
	
	if (size > 0)
	{
		memcpy(buffer,[data bytes],[data length]);
	}
	//[data getBytes:buffer];
	return size;
}


#import "CKConnectionProtocol.h"
#import "CKTransferRecord.h"
#import "NSString+Connection.h"

NSString *CKTransferRecordProgressChangedNotification = @"CKTransferRecordProgressChangedNotification";
NSString *CKTransferRecordTransferDidBeginNotification = @"CKTransferRecordTransferDidBeginNotification";
NSString *CKTransferRecordTransferDidFinishNotification = @"CKTransferRecordTransferDidFinishNotification";

@interface CKTransferRecord (PrivateMethods)
- (id)_initWithConnection:(id <CKConnection>)connection
				localPath:(NSString *)localPath
			   remotePath:(NSString *)remotePath
					 size:(unsigned long long)size 
				 isUpload:(BOOL)isUploadFlag
			  isDirectory:(BOOL)isDirectoryFlag;
- (void)_appendToDescription:(NSMutableString *)str indentation:(unsigned)indent;
- (void)_sizeWithChildrenChangedBy:(unsigned long long)sizeDelta;
@end

@implementation CKTransferRecord

#pragma mark -
#pragma mark NSObject Overrides

+ (NSSet *)keyPathsForValuesAffectingNameWithProgress
{
    return [NSSet setWithObjects:@"progress", nil];
}

+ (NSSet *)keyPathsForValuesAffectingNameWithProgressAndFileSize
{
    return [NSSet setWithObjects:@"progress", @"name", @"size", nil];
}

+ (NSSet *)keyPathsForValuesAffectingName
{
    return [NSSet setWithObjects:@"localPath", @"remotePath", nil];
}

+ (NSSet *)keyPathsForValuesProgress
{
    return [NSSet setWithObjects:@"size", nil];
}

+ (NSSet *)keyPathsForValuesIsLeaf
{
    return [NSSet setWithObjects:@"isDiscoveringFilesToDownload", nil];
}

- (void)willChangeValueForKey:(NSString *)key
{
	//We override this because we need to call the same on the record's parents to update any bindings on them as well. This traverses all the way up the parental hierarchy.
	[super willChangeValueForKey:key];
	
	if ([self parent])
		[[self parent] willChangeValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key
{
	//We override this because we need to call the same on the record's parents to update any bindings on them as well. This traverses all the way up the parental hierarchy.
	[super didChangeValueForKey:key];
	
	if ([self parent])
		[[self parent] didChangeValueForKey:key];
}

- (id)copyWithZone:(NSZone *)zone
{
	CKTransferRecord *recordCopy = [[CKTransferRecord allocWithZone:zone] _initWithConnection:_connection
																					localPath:_localPath
																				   remotePath:_remotePath
																						 size:_sizeInBytes
																					 isUpload:_isUpload
																				  isDirectory:_isDirectory];
	
	[recordCopy setError:_error];
	
	//Add all the children (recursively)
	NSEnumerator *childEnumerator = [_children objectEnumerator];
	CKTransferRecord *child;
	while ((child = [childEnumerator nextObject]))
	{
		CKTransferRecord *childCopy = [child copy]; //Calls this method with a nil zone
		[recordCopy addChild:childCopy];
	}
	
	//Add all the properties
	NSEnumerator *propertyKeyEnumerator = [_properties keyEnumerator];
	id key;
	while ((key = [propertyKeyEnumerator nextObject]))
		[recordCopy setProperty:[self propertyForKey:key] forKey:key];
	
	return recordCopy;
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self _appendToDescription:str indentation:0];
	return str;
}

- (void)dealloc
{
	[_children makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	[_children release];
	[_properties release];
	[_error release];
	[super dealloc];
}

#pragma mark -
#pragma mark Creation

+ (CKTransferRecord *)uploadRecordForConnection:(id <CKConnection>)connection
									  sourceLocalPath:(NSString *)sourceLocalPath 
								destinationRemotePath:(NSString *)destinationRemotePath
										   size:(unsigned long long)size 
									isDirectory:(BOOL)isDirectoryFlag
{
	return [[[CKTransferRecord alloc] _initWithConnection:connection
												localPath:sourceLocalPath
											   remotePath:destinationRemotePath
													 size:size 
												 isUpload:YES
											  isDirectory:isDirectoryFlag] autorelease];
}

+ (CKTransferRecord *)downloadRecordForConnection:(id <CKConnection>)connection
										 sourceRemotePath:(NSString *)sourceRemotePath
									 destinationLocalPath:(NSString *)destinationLocalPath
													 size:(unsigned long long)size
									  isDirectory:(BOOL)isDirectoryFlag
{
	return [[[CKTransferRecord alloc] _initWithConnection:connection
												localPath:destinationLocalPath
											   remotePath:sourceRemotePath
													 size:size 
												 isUpload:NO
											  isDirectory:isDirectoryFlag] autorelease];
}		

- (id)_initWithConnection:(id <CKConnection>)connection
				localPath:(NSString *)localPath
			   remotePath:(NSString *)remotePath
					 size:(unsigned long long)size 
				 isUpload:(BOOL)isUploadFlag
			  isDirectory:(BOOL)isDirectoryFlag
{
	if ((self = [super init])) 
	{
		_isUpload = isUploadFlag;
		_isDirectory = isDirectoryFlag;
		_connection = connection;
		_localPath = [localPath copy];
		_remotePath = [remotePath copy];
		_sizeInBytes = size;
		_children = [[NSMutableArray array] retain];
		_properties = [[NSMutableDictionary dictionary] retain];
		_error = nil;
		_progress = 0;
		return self;
	}
	return nil;
}


#pragma mark -
#pragma mark Core
- (NSString *)name
{
	@synchronized (self)
	{
		//There is no reason _localPath or _remotePath should either, EVER, be nil, but if they are, fall back on one another.
		if (_localPath)
			return [_localPath lastPathComponent];
		if (_remotePath)
			return [_remotePath lastPathComponent];
	}
	return nil;
}

- (void)setLocalPath:(NSString *)newLocalPath
{
	//As in +initialize, @"name", is dependent on @"localPath"
	@synchronized (self)
	{
		if (_localPath == newLocalPath)
			return;
		
		[_localPath release];
		_localPath = [newLocalPath copy];
	}
}

- (NSString *)localPath
{
	@synchronized (self)
	{
		return [NSString stringWithString:_localPath];
	}
	return nil;
}

- (void)setRemotePath:(NSString *)newRemotePath
{
	//As in +initialize, @"name", is dependent on @"remotePath"
	@synchronized (self)
	{
		if (_remotePath == newRemotePath)
			return;
		
		[_remotePath release];
		_remotePath = [newRemotePath copy];
	}
}

- (NSString *)remotePath
{
	@synchronized (self)
	{
		return [NSString stringWithString:_remotePath];
	}
	return nil;
}

- (CKTransferRecord *)root
{
	@synchronized (self)
	{
		if (_parent)
		{
			return [_parent root];
		}
		return self;
	}
	return nil;
}

- (void)setParent:(CKTransferRecord *)parent
{
	@synchronized (self)
	{
		_parent = parent;
	}
}

- (CKTransferRecord *)parent
{
	@synchronized (self)
	{
		return _parent;
	}
	return nil;
}

#pragma mark -
- (void)setIsDiscoveringFilesToDownload:(BOOL)flag
{
	@synchronized (self)
	{
		_isDiscoveringFilesToDownload = flag;
	}
}

- (BOOL)isDiscoveringFilesToDownload
{
	@synchronized (self)
	{
		return _isDiscoveringFilesToDownload;
	}
	return NO;
}

#pragma mark -
- (BOOL)isUpload
{ 
	return _isUpload;
}

- (BOOL)isDirectory
{
	@synchronized (self)
	{
		return _isDirectory;
	}
	return NO;
}

#pragma mark -
- (void)setConnection:(id <CKConnection>)connection
{
	@synchronized (self)
	{
		_connection = connection;
	}
}

- (id <CKConnection>)connection
{
	@synchronized (self)
	{
		return _connection;
	}
	return nil;
}

- (void)cancel:(id)sender
{
	if ([self connection])
		[[self connection] cancelTransfer];
}

#pragma mark -
- (void)addChild:(CKTransferRecord *)record
{
	NSParameterAssert(record);
    
	@synchronized (self)
	{
		[self willChangeValueForKey:@"contents"];
		[_children addObject:record];
		[record setParent:self];
		[self didChangeValueForKey:@"contents"];
		
		[self _sizeWithChildrenChangedBy:[record size]];
	}
}

- (NSArray *)children
{
	@synchronized (self)
	{
		return [[_children copy] autorelease];
	}
	return nil;
}

- (CKTransferRecord *)childTransferRecordForRemotePath:(NSString *)remotePath
{
	@synchronized (self)
	{
		//Are we actually the record we're supposed to find?
		if ([remotePath isEqualToString:[self remotePath]])
			return self;
		
		//If the remotePath doesn't have the target prefix, we can't possibly have a child with it.
		if (![remotePath hasPrefix:[self remotePath]])
			return nil;
		
		NSEnumerator *childrenEnumerator = [_children objectEnumerator];
		CKTransferRecord *child;
		while ((child = [childrenEnumerator nextObject]))
		{
			//Is one of our children what we're looking for?
			if ([[child remotePath] isEqualToString:remotePath])
				return child;
			
			//It's not one of children, but if it's one of our children's children, our child will be a prefix of the remotePath
			if (![remotePath hasPrefix:[child remotePath]])
				continue;
			
			//The target is a child of child.
			return [child childTransferRecordForRemotePath:remotePath];
		}
	}
	
	return nil;
}

#pragma mark -

- (void)setProperty:(id)property forKey:(id)key
{
	NSParameterAssert(property);
	NSParameterAssert(key);	
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(id)key
{
	NSParameterAssert(key);
	return [_properties objectForKey:key];
}

- (void)removePropertyForKey:(id)key
{
	NSParameterAssert(key);
	[_properties removeObjectForKey:key];
}

- (void)setObject:(id)object forKey:(id)key
{
	[self setProperty:object forKey:key];
}

- (id)objectForKey:(id)key
{
	return [self propertyForKey:key];
}

- (void)removeObjectForKey:(id)key
{
	[self removePropertyForKey:key];
}

#pragma mark -
- (void)setSize:(unsigned long long)size
{
	//As in +initialize, @"progress" is a dependent key on @"size"
	@synchronized (self)
	{
		if (_sizeInBytes != 0)
		{
			//We're updating our size. We need to update our parents' sizes too.
			unsigned long long sizeDelta = size - _sizeInBytes;
			[self _sizeWithChildrenChangedBy:sizeDelta];
		}
		_sizeInBytes = size;
	}
}

- (unsigned long long)size
{
	@synchronized (self)
	{
		//Have we already calculated our size with children?
		if (_sizeInBytesWithChildren != 0)
			return _sizeInBytesWithChildren;
		
		//Calculate our size including our children
		unsigned long long size = _sizeInBytes;
		NSEnumerator *e = [_children objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur respondsToSelector:@selector(size)])
			{
				size += [cur size];
			}
			else
			{
				NSLog(@"CKTransferRecord content object does not have 'size'");		// work around bogus children?
			}
		}
		_sizeInBytesWithChildren = size;
		return size;
	}
	return 0;
}

- (void)_sizeWithChildrenChangedBy:(unsigned long long)sizeDelta
{
	if (sizeDelta == 0)
		return;
	
	[self willChangeValueForKey:@"size"];
	
	//As soon as pass this point, we only rely on _sizeInBytesWithChildren. So if this is our first use of _sizeInBytesWithChildren, let's make sure it reflects _our_ size too.
	if (_sizeInBytesWithChildren == 0)
		_sizeInBytesWithChildren = _sizeInBytes;
	
	_sizeInBytesWithChildren += sizeDelta;
	[self didChangeValueForKey:@"size"];
	
	if ([self parent])
		[[self parent] _sizeWithChildrenChangedBy:sizeDelta];
}

#pragma mark -
- (unsigned long long)transferred
{
	if ([self isDirectory]) 
	{
		unsigned long long rem = 0;
		NSEnumerator *e = [[self children] objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject])) 
		{
			rem += [cur transferred];
		}
		return rem;
	}
	if (_progress == -1) //if we have an error return it as if we transferred the lot of it
	{
		return _sizeInBytes;
	}
	return _bytesTransferred;
}

- (float)speed
{
	/*
		We have two modes of speed calculation for directories. If a directory has children which report non-zero speeds themselves, the setSpeed: calls coalesce up the hierarchy (see setSpeed: for why). On small files, speed is often not calculated at all, and remains at zero. In this case, the directory's speed will otherwise remain at zero, so we perform a simplistic calculation of overall speed -- the directory's transferred byte count, divided by its elapsed time. We update this simplistic speed at most at one second intervals. As you will see in setSpeed, we reset the _lastDirectorySpeedUpdateTime when we receive a real non-zero speed (from a child), to allow this method to return the more accurate speed we received from a child.
	 */
	@synchronized (self)
	{
		//This logic only allows us to perform simple directory speed calculation if we are both a directory and do not have a real non-zero speed from a child.
		if ([self isDirectory] && (_speed == 0.0 || _lastDirectorySpeedUpdateTime != 0.0))
		{
			NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
			NSTimeInterval timeSinceLastDirectorySpeedUpdate = now - _lastDirectorySpeedUpdateTime;
			
			BOOL canUpdateNow = (_lastDirectorySpeedUpdateTime == 0.0 || timeSinceLastDirectorySpeedUpdate >= 1.0);
			if (canUpdateNow)
			{
				_lastDirectorySpeedUpdateTime = now;
				_speed = ([self transferred] / [self elapsedTransferTime]);
			}
		}		
		return _speed;
	}
	
	return 0.0;
}

- (void)setSpeed:(float)speed
{
	@synchronized (self)
	{
		//Reset the directory speed update time. See note in -speed for why we're doing this.
		_lastDirectorySpeedUpdateTime = 0.0;
		if (_speed == speed)
			return;
		
		_speed = speed;
		
		//Our parent's speed is dependent on ours.
		if ([self parent])
			[[self parent] setSpeed:speed];
	}
}

- (void)forceAnimationUpdate
{
	NSInteger i;
	for (i = 1; i <= 4; i++)
	{
		[self willChangeValueForKey:@"progress"];
		_progress = i * 25;
		[self didChangeValueForKey:@"progress"];
		[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification
															object:self];
	}
}

- (void)setProgress:(NSInteger)progress
{
	@synchronized (self)
	{
		if (_progress != progress || progress == 100)
		{
			if (progress == 100 && _progress == 1)
			{
				[self forceAnimationUpdate];
				return;
			}
			
			_progress = progress;
			
			[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification object:self];
		}
	}
}

- (NSInteger)progress
{
	@synchronized (self)
	{
		// Check if self or descendents have an error, so we can show that error.
		if ([self hasError])
		{
			return -1;
		}
		
		if ([self isDiscoveringFilesToDownload])
			return 0;
		
		if ([self isDirectory]) 
		{
			//get the real transfer progress of the whole directory
			unsigned long long size = [self size];
			unsigned long long transferred = [self transferred];
			if (size == 0) size = 1;
			NSInteger percent = (NSInteger)((transferred / (size * 1.0)) * 100);
			return percent;
		}
		return _progress;
	}
	return 0;
}

- (NSTimeInterval)elapsedTransferTime
{
	return ([NSDate timeIntervalSinceReferenceDate] - _transferStartTime);
}

#pragma mark -
- (NSError *)error
{
	@synchronized (self)
	{
		return _error;
	}
	return nil;
}

- (BOOL)problemsTransferringCountingErrors:(NSInteger *)outErrors successes:(NSInteger *)outSuccesses
{
	if (![self isDirectory])
	{
		if (_error != nil)
		{
			(*outErrors)++;
		}
		else
		{
			(*outSuccesses)++;
		}
	}
	else
	{
		// check children for errors
		NSEnumerator *e = [[self children] objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			(void) [cur problemsTransferringCountingErrors:outErrors successes:outSuccesses];
		}
	}
	return (*outErrors > 0);	// return if there were any problems
}

- (BOOL)hasError
{
	return (_error != nil);
}

- (void)setError:(NSError *)error
{
	@synchronized (self)
	{
		if (error != _error)
		{
			[self willChangeValueForKey:@"progress"]; // we use this because we return -1 on an error
			[_error autorelease];
			_error = [error retain];
			[self didChangeValueForKey:@"progress"];
			[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification object:self];
		}
		
		//Set the error on all parents, too.
		if ([self parent])
			[[self parent] setError:error];
	}
}


#pragma mark -
#pragma mark Private Extras
- (void)_appendToDescription:(NSMutableString *)str indentation:(unsigned)indent
{
	@synchronized (self)
	{
		NSInteger i;
		for (i = 0; i < indent; i++)
		{
			[str appendString:@"\t"];
		}
		
		[str appendFormat:@"\t%@", [self name]];
		
		if ([self isDirectory])
		{
			[str appendString:@"/"];
		}
		[str appendFormat:@"\t(%llu of %llu bytes - %i%%)\n", [self transferred], [self size], [self progress]];
		
		NSEnumerator *e = [_children objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			[cur _appendToDescription:str indentation:indent+1];
		}
	}
}

#pragma mark -
#pragma mark Connection Transfer Delegate
- (void)transferDidBegin:(CKTransferRecord *)transfer
{
	//We can be called by children, informing us that they've begun. If we already got that notice from another child, as a directory, ignore it.
	if (_transferStartTime != 0.0)
		return;
	
	_bytesTransferred = 0;
	_bytesTransferredSinceLastSpeedUpdate = 0;
	_lastSpeedUpdateTime = [NSDate timeIntervalSinceReferenceDate];
	_transferStartTime = [NSDate timeIntervalSinceReferenceDate];
	
	[self setProgress:0];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidBeginNotification 
														object:self];
	if ([self parent])
		[[self parent] transferDidBegin:[self parent]];
}

- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length
{
	_bytesTransferred += length;
	_bytesTransferredSinceLastSpeedUpdate += length;
	
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval timeSinceLastSpeedUpdate = now - _lastSpeedUpdateTime;
	
	if (timeSinceLastSpeedUpdate > 2.0 || _bytesTransferred == _sizeInBytes)
	{
		//We're above the threshold, and we changed transferred.
		[self willChangeValueForKey:@"transferred"];
		[self didChangeValueForKey:@"transferred"];
		
		//Recalculate our speed.
		if (_bytesTransferred == _sizeInBytes)
			[self setSpeed:0.0];
		else
			[self setSpeed:((double)_bytesTransferredSinceLastSpeedUpdate) / timeSinceLastSpeedUpdate];
		
		_bytesTransferredSinceLastSpeedUpdate = 0;
		_lastSpeedUpdateTime = now;
	}
}

- (void)transfer:(CKTransferRecord *)transfer progressedTo:(NSNumber *)percent
{
	[self setProgress:[percent intValue]];
}

- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error
{
	//If we get _any_ error while we're uploading, we're "finished" albeit with an error. Handle it as such.
	[self transferDidFinish:transfer error:error];
}

- (void)transferDidFinish:(CKTransferRecord *)transfer error:(NSError *)error
{
	[self setError:error];
	_bytesTransferredSinceLastSpeedUpdate = (_sizeInBytes - _bytesTransferred);
	_bytesTransferred = _sizeInBytes;
	_lastSpeedUpdateTime = [NSDate timeIntervalSinceReferenceDate];
	[self setProgress:100];
	[self setSpeed:0.0];

	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidFinishNotification object:self];
	
	//If parent is finished, they need notifications too.
	CKTransferRecord *parent = [self parent];
	if (parent && [parent transferred] == [parent size])
		[parent transferDidFinish:parent error:error];
}

#pragma mark -
#pragma mark NSTreeController Support
- (BOOL)isLeaf
{
	@synchronized (self)
	{
		return (![self isDirectory] || [self isDiscoveringFilesToDownload]);
	}
	return YES;
}

- (NSDictionary *)nameWithProgress
{
	NSNumber *progress = nil;
	if ([self hasError])
	{
		progress = [NSNumber numberWithInt:-1];
	}
	else
	{
		progress = [NSNumber numberWithInt:[self progress]];
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:progress, @"progress", [self name], @"name", nil];
}

- (void)setNameWithProgress:(id)notused
{
	; // just for KVO bindings
}

/*  The same as -nameWithProgress, but also includes the file size in brackets if appropriate
 */
- (NSDictionary *)nameWithProgressAndFileSize
{
    NSDictionary *result = [self nameWithProgress];
    
    // Directories should not display their size info
    if (_sizeInBytes > 0 && [[self children] count] == 0)  // Use _size to ignore children's sizes
    {
        // Calculate the size of the transfer in a user-friendly manner
        NSString *fileSize = [NSString formattedFileSize:(double)[self size]];
        NSString *unattributedDescription = [[NSString alloc] initWithFormat:@"%@ (%@)", [self name], fileSize];
        
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSRegularControlSize]]
                                                               forKey:NSFontAttributeName];
        
        NSMutableAttributedString *description = [[NSMutableAttributedString alloc] initWithString:unattributedDescription attributes:attributes];
        [unattributedDescription release];
        
        // Make the size info in grey
        [description addAttribute:NSForegroundColorAttributeName
                            value:[NSColor grayColor]
                            range:NSMakeRange([[self name] length] + 1, [fileSize length] + 2)];
        
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  [result objectForKey:@"progress"], @"progress",
                  description, @"name",
                  nil];
        
        [description release];
    }
    
    return result;
}
@end
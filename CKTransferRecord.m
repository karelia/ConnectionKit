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

#import "CKConnectionProtocol.h"
#import "CKTransferRecord.h"
#import "NSString+Connection.h"

NSString *CKTransferRecordProgressChangedNotification = @"CKTransferRecordProgressChangedNotification";
NSString *CKTransferRecordTransferDidBeginNotification = @"CKTransferRecordTransferDidBeginNotification";
NSString *CKTransferRecordTransferDidFinishNotification = @"CKTransferRecordTransferDidFinishNotification";

@implementation CKTransferRecord

#pragma mark -
#pragma mark NSObject Overrides
+ (void)initialize
{
	[CKTransferRecord setKeys:[NSArray arrayWithObject:@"progress"] triggerChangeNotificationsForDependentKey:@"nameWithProgress"];
    [CKTransferRecord setKeys:[NSArray arrayWithObjects:@"progress", @"name", @"size", nil]
triggerChangeNotificationsForDependentKey:@"nameWithProgressAndFileSize"];
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

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self appendToDescription:str indentation:0];
	return str;
}

- (void)dealloc
{
	[_name release];
	[_contents makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	[_contents release];
	[_properties release];
	[_error release];
	[super dealloc];
}

#pragma mark -
#pragma mark Creation
+ (id)recordWithName:(NSString *)name size:(unsigned long long)size
{
	return [[[CKTransferRecord alloc] initWithName:name size:size] autorelease];
}

- (id)initWithName:(NSString *)name size:(unsigned long long)size
{
	if ((self = [super init])) 
	{
		_name = [name copy];
		_sizeInBytes = size;
		_contents = [[NSMutableArray array] retain];
		_properties = [[NSMutableDictionary dictionary] retain];
		_error = nil;
		_progress = 0;
	}
	return self;
}


#pragma mark -
#pragma mark Core
- (BOOL)isUpload
{ 
	return _isUpload;
}

- (NSString *)name
{
	return _name;
}

- (id <CKConnection>)connection
{
	return _connection;
}

- (CKTransferRecord *)parent
{
	return _parent;
}

- (void)cancel:(id)sender
{
	if ([self connection])
		[[self connection] cancelTransfer];
}

- (BOOL)isDirectory
{
	return [_contents count] > 0;
}

- (CKTransferRecord *)root
{
	if (_parent)
	{
		return [_parent root];
	}
	return self;
}

- (NSString *)path
{
	if ([self parent])
    {
        return [[_parent path] stringByAppendingPathComponent:[self name]];	// Old code was @"%@/%@" but it broke if _parent was just /
    }
    else
    {
		return [self name];
	}
}

- (void)addChild:(CKTransferRecord *)record
{
	NSParameterAssert(record);
    
    [self willChangeValueForKey:@"contents"];
	[_contents addObject:record];
	[record setParent:self];
	[self didChangeValueForKey:@"contents"];
}

- (NSArray *)contents
{
	return [[_contents copy] autorelease];
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	/// Terrence added this NSLog since the exception doesn't log the key
	if ( nil == property )
	{
		NSLog(@"attempted to set nil property for key %@", key);
	}
	
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
}

// keep NSDictionary accessor compatible so we can move over internal use of this class
- (void)setObject:(id)object forKey:(id)key
{
	[self setProperty:object forKey:key];
}

- (id)objectForKey:(id)key
{
	return [self propertyForKey:key];
}

- (void)appendToDescription:(NSMutableString *)str indentation:(unsigned)indent
{
	NSInteger i;
	for (i = 0; i < indent; i++)
	{
		[str appendString:@"\t"];
	}	
	[str appendFormat:@"\t%@", _name];
	if ([self isDirectory])
	{
		[str appendString:@"/"];
	}
	[str appendFormat:@"\t(%lld of %lld bytes - %@%%)\n", [self transferred], [self size], [self progress]];
	
	NSEnumerator *e = [[self contents] objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		[cur appendToDescription:str indentation:indent+1];
	}
}

#pragma mark Size
- (unsigned long long)size
{
	//Have we already calculated our size with children?
	if (_sizeInBytesWithChildren != 0)
		return _sizeInBytesWithChildren;
	
	//Calculate our size including our children
	unsigned long long size = _sizeInBytes;
	NSEnumerator *e = [[self contents] objectEnumerator];
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

- (void)_sizeWithChildrenChangedBy:(unsigned long long)sizeDelta
{
	_sizeInBytesWithChildren += sizeDelta;
	if ([self parent])
		[[self parent] _sizeWithChildrenChangedBy:sizeDelta];
}

#pragma mark Progress
- (unsigned long long)transferred
{
	if ([self isDirectory]) 
	{
		unsigned long long rem = 0;
		NSEnumerator *e = [[self contents] objectEnumerator];
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
	return _numberOfBytesTransferred;
}

- (float)speed
{
	if ([self isDirectory]) 
	{
		if (_transferStartTime == 0.0)
		{
			_transferStartTime = [NSDate timeIntervalSinceReferenceDate];
		}
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
		if (_lastDirectorySpeedUpdate == 0.0 || now - _lastDirectorySpeedUpdate >= 1.0)
		{
			_lastDirectorySpeedUpdate = now;
			NSTimeInterval elapsedTime = now - _transferStartTime;

			[self willChangeValueForKey:@"speed"];
			if (elapsedTime == 0.0)
			{
				//If we don't catch this, we are effectively dividing by zero below. This would leave _speed as NaN.
				_speed = 0.0;
			}
			else
			{
				unsigned long long transferred = [self transferred];
				_speed = transferred / elapsedTime;
			}
			[self didChangeValueForKey:@"speed"];
		}
	}
	return _speed;
}

- (void)setSpeed:(float)speed
{
	if (speed != _speed)
	{
		[self willChangeValueForKey:@"speed"];
		_speed = speed;
		[self didChangeValueForKey:@"speed"];
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
	if (_progress != progress || progress == 100)
	{
		if (progress == 100 && _progress == 1)
		{
			[self forceAnimationUpdate];
			return;
		}
		
		[self willChangeValueForKey:@"progress"];
		_progress = progress;
		[self didChangeValueForKey:@"progress"];
		
		
		[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordProgressChangedNotification object:self];
	}
}

- (NSInteger)progress
{
	// Check if self of descendents have an error, so we can show that error.
	if ([self hasError])
	{
		return -1;
	}
	
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

#pragma mark Errors
- (NSError *)error
{
	return _error;
}

- (BOOL)problemsTransferringCountingErrors:(NSInteger *)outErrors successes:(NSInteger *)outSuccesses
{
	if ([self isLeaf])
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
		NSEnumerator *e = [[self contents] objectEnumerator];
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

- (void)setParent:(CKTransferRecord *)parent
{
	_parent = parent;
	if (_parent)
		[_parent _sizeWithChildrenChangedBy:_sizeInBytes];
}

#pragma mark -
#pragma mark Connection Transfer Delegate

- (void)transferDidBegin:(CKTransferRecord *)transfer
{
	_numberOfBytesTransferred = 0;
	_numberOfBytesInLastTransferChunk = 0;
	_lastTransferTime = [NSDate timeIntervalSinceReferenceDate];
	[self setProgress:0];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidBeginNotification object:self];
}

- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length
{
	_numberOfBytesTransferred += length;
	_numberOfBytesInLastTransferChunk += length;
	
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval difference = now - _lastTransferTime;
	
	if (difference > 2.0 || _numberOfBytesTransferred == _sizeInBytes)
	{
		[self willChangeValueForKey:@"speed"];
		if (_numberOfBytesTransferred == _sizeInBytes)
		{
			[self setSpeed:0.0];
		}
		else
		{
			[self setSpeed:((double)_numberOfBytesInLastTransferChunk) / difference];
		}
		_numberOfBytesInLastTransferChunk = 0;
		_lastTransferTime = now;
		[self didChangeValueForKey:@"speed"];
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
	_numberOfBytesInLastTransferChunk = (_sizeInBytes - _numberOfBytesTransferred);
	_numberOfBytesTransferred = _sizeInBytes;
	_lastTransferTime = [NSDate timeIntervalSinceReferenceDate];
	[self setProgress:100];

	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidFinishNotification object:self];
	
	//If parent is finished, they need notifications too.
	CKTransferRecord *parent = [self parent];
	if (parent && [parent transferred] == [parent size])
		[parent transferDidFinish:parent error:error];
}

#pragma mark -
#pragma mark CKTransferController Support


#pragma mark -
#pragma mark NSTreeController Support
- (BOOL)isLeaf
{
	return [_contents count] == 0;
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
    if (_sizeInBytes > 0 && [[self contents] count] == 0)  // Use _size to ignore children's sizes
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

#pragma mark -
#pragma mark Setters
- (void)setUpload:(BOOL)flag
{
	_isUpload = flag;
}
- (void)setName:(NSString *)name
{
	if (_name == name)
		return;
	
	[self willChangeValueForKey:@"name"];
	[_name release];
	_name = [name copy];
	[self didChangeValueForKey:@"name"];
}

- (void)setConnection:(id <CKConnection>)connection
{
	_connection = connection;
}

- (void)setSize:(unsigned long long)size
{
	[self willChangeValueForKey:@"progress"];
	if (_sizeInBytes != 0)
	{
		//We're updating our size. We need to update our parents' sizes too.
		unsigned long long sizeDelta = size - _sizeInBytes;
		[self _sizeWithChildrenChangedBy:sizeDelta];
	}
	_sizeInBytes = size;
	[self didChangeValueForKey:@"progress"];
}

@end

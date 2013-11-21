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

#import "CKTransferRecord.h"

#import "CK2FileOperation.h"

#import <AppKit/AppKit.h>   // for NSColor


NSString *CKTransferRecordTransferDidBeginNotification = @"CKTransferRecordTransferDidBeginNotification";
NSString *CKTransferRecordTransferDidFinishNotification = @"CKTransferRecordTransferDidFinishNotification";

@implementation CKTransferRecord

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
	if (_name != name)
	{
		[self willChangeValueForKey:@"name"];
		name = [name copy];
		[_name release];
		_name = name;
		[self didChangeValueForKey:@"name"];
	}
}

@synthesize uploadOperation = _operation;

- (BOOL)isFinished;
{
    CK2FileOperation *operation = self.uploadOperation;
    if (operation) return (operation.state == CK2FileOperationStateCompleted);
    
    for (CKTransferRecord *aRecord in self.contents)
    {
        if (!aRecord.isFinished) return NO;
    }
    
    return YES;
}

- (NSError *)error
{
    CK2FileOperation *operation = self.uploadOperation;
    if (operation) return operation.error;
    
    NSError *result = nil;
    for (CKTransferRecord *aRecord in self.contents)
    {
        result = aRecord.error;
        if (result) break;
    }
    
    return result;
}

- (CKTransferRecord *)parent { return _parent; }

+ (instancetype)recordWithName:(NSString *)name uploadOperation:(CK2FileOperation *)operation;
{
	return [[[CKTransferRecord alloc] initWithName:name uploadOperation:operation] autorelease];
}

- (id)initWithName:(NSString *)name uploadOperation:(CK2FileOperation *)operation;
{
	if ((self = [super init])) 
	{
		_name = [name copy];
        _operation = [operation retain];
		_contents = [[NSMutableArray array] retain];
		_properties = [[NSMutableDictionary dictionary] retain];
        
        // Cache initial size estimate. Don't want it to change if request needs retransmitting
        _size = operation.countOfBytesExpectedToWrite;
	}
	return self;
}

- (void)dealloc
{
	[_name release];
    [_operation release];
	[_contents makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	[_contents release];
	[_properties release];

	[super dealloc];
}

- (int64_t)size
{
	// Calculate our size including our children
	int64_t result = _size;
	
    for (CKTransferRecord *aRecord in self.contents)
    {
        result += [aRecord size];
    }
	
	return result;
}

- (unsigned long long)transferred
{
	int64_t result = self.uploadOperation.countOfBytesWritten;
    
    for (CKTransferRecord *aRecord in _contents)    // -contents is too slow as copies the internal storage
    {
        result += aRecord.transferred;
    }
    
	return result;
}

- (CGFloat)speed
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

- (void)setSpeed:(CGFloat)speed
{
	if (speed != _speed)
	{
		[self willChangeValueForKey:@"speed"];
		_speed = speed;
		[self didChangeValueForKey:@"speed"];
	}
}

- (CGFloat)progress
{
    CK2FileOperation *op = self.uploadOperation;
    __block int64_t totalWritten = op.countOfBytesWritten;
    
    __block int64_t totalExpected = op.countOfBytesExpectedToWrite;
    if (totalWritten > totalExpected) totalExpected = totalWritten;
    
    [self enumerateTransferRecordsRecursively:YES usingBlock:^(CKTransferRecord *record) {
        
        CK2FileOperation *op = record.uploadOperation;
        int64_t written = op.countOfBytesWritten;
        
        int64_t expected = op.countOfBytesExpectedToWrite;
        if (written > expected) expected = written;
        
        totalWritten += written;
        totalExpected += expected;
    }];
    
    if (!totalExpected) return 0;
    return (100 * totalWritten) / totalExpected;
}

- (void)enumerateTransferRecordsRecursively:(BOOL)recursive usingBlock:(void (^)(CKTransferRecord *record))block;
{
    [self.contents enumerateObjectsUsingBlock:^(CKTransferRecord *record, NSUInteger idx, BOOL *stop) {
        
        block(record);
        if (recursive) [record enumerateTransferRecordsRecursively:recursive usingBlock:block];
    }];
}

- (BOOL)problemsTransferringCountingErrors:(NSInteger *)outErrors successes:(NSInteger *)outSuccesses
{
	if ([self isLeaf])
	{
		if (self.error)
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

- (void)setParent:(CKTransferRecord *)parent
{
	_parent = parent;
}

- (BOOL)isDirectory
{
	return [_contents count] > 0;
}

#pragma mark KVO

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

- (void *)observationInfo; { return _observationInfo; }
- (void)setObservationInfo:(void *)observationInfo; { _observationInfo = observationInfo; }

#pragma mark

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

- (void)addContent:(CKTransferRecord *)record
{
	NSParameterAssert(record);
    
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:[_contents count]];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"contents"];
    {{
        [_contents addObject:record];
        [record setParent:self];
    }}
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"contents"];
}

- (NSArray *)contents
{
	return [[_contents copy] autorelease];
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
	[str appendFormat:@"\t(%lld of %lld bytes - %li%%)\n", [self transferred], [self size], (long) [self progress]];

	NSEnumerator *e = [[self contents] objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		[cur appendToDescription:str indentation:indent+1];
	}
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithString:@"\n"];
	[self appendToDescription:str indentation:0];
	return str;
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
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

#pragma mark -
#pragma mark Connection Transfer Delegate

- (void)transferDidBegin:(CKTransferRecord *)transfer
{
	_lastTransferTime = [NSDate timeIntervalSinceReferenceDate];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidBeginNotification object:self];
}

- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length
{
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval difference = now - _lastTransferTime;
	
	if (difference > 2.0 || self.transferred == self.size)
	{
		[self willChangeValueForKey:@"speed"];
		if (self.transferred == self.size)
		{
			[self setSpeed:0.0];
		}
		else
		{
			[self setSpeed:((double)self.transferred) / difference];
		}
		_lastTransferTime = now;
		[self didChangeValueForKey:@"speed"];
	}
}

- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error
{
	//If we get _any_ error while we're uploading, we're "finished" albeit with an error. Handle it as such.
	[self transferDidFinish:transfer error:error];
}

- (void)transferDidFinish:(CKTransferRecord *)transfer error:(NSError *)error
{
	_lastTransferTime = [NSDate timeIntervalSinceReferenceDate];

	[[NSNotificationCenter defaultCenter] postNotificationName:CKTransferRecordTransferDidFinishNotification object:self];
	
	//If parent is finished, they need notifications too.
	CKTransferRecord *parent = [self parent];
	if (parent && [parent transferred] == [parent size])
		[parent transferDidFinish:parent error:error];
}

#pragma mark -
#pragma mark Recursive File Transfer Methods

+ (CKTransferRecord *)rootRecordWithPath:(NSString *)path
{
	CKTransferRecord *result = [CKTransferRecord recordWithName:@"" uploadOperation:nil];
    
	NSArray *pathComponents = [path pathComponents];
	if ([pathComponents count] > 0)
    {
        [result setName:[[path pathComponents] objectAtIndex:0]];  // -firstPathComponent ignores the root dir for absolute paths
        CKTransferRecord *thisNode, *subNode = result;
        
        for (NSUInteger i = 1; i < [pathComponents count]; i++)
        {
            thisNode = [CKTransferRecord recordWithName:[pathComponents objectAtIndex:i] uploadOperation:nil];
            [subNode addContent:thisNode];
            subNode = thisNode;
        }
	}
    
	return result;
}

- (CKTransferRecord *)recordForPath:(NSString *)path;
{
    NSParameterAssert(path);
    
    if ([path length] == 0) return self;
    
    if ([path isAbsolutePath])
    {
        path = [path substringFromIndex:1]; // should make it relative, if not we'll go round again
        return [[self root] recordForPath:path];
    }
    
    
    NSArray *components = [path pathComponents];
    NSString *name = [components objectAtIndex:0];
    
    for (CKTransferRecord *aRecord in [self contents]) 
    {
        if ([[aRecord name] isEqualToString:name])
        {
            NSString *newPath = [NSString pathWithComponents:
                                 [components subarrayWithRange:NSMakeRange(1, [components count]-1)]];
            
            return [aRecord recordForPath:newPath];
        }
    }
	
    return nil;
}

#pragma mark -
#pragma mark NSTreeController support

- (BOOL)isLeaf
{
	return [_contents count] == 0;
}

- (NSDictionary *)nameWithProgress
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
            @(self.progress), @"progress",
            self.name, @"name",
            @(self.isFinished && !self.error), @"finished",
            self.error, @"error",
            nil];
}
+ (NSSet *)keyPathsForValuesAffectingNameWithProgress;
{
    return [NSSet setWithObject:@"progress"];
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
    if (self.uploadOperation && [[self contents] count] == 0)
    {
        // Calculate the size of the transfer in a user-friendly manner
        NSString *fileSize = [self.class formattedFileSize:(double)[self size]];
        NSString *unattributedDescription = [[NSString alloc] initWithFormat:@"%@ (%@)", [self name], fileSize];
        
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSRegularControlSize]]
                                                               forKey:NSFontAttributeName];
        
        NSMutableAttributedString *description = [[NSMutableAttributedString alloc] initWithString:unattributedDescription attributes:attributes];
        [unattributedDescription release];
        
        // Make the size info in grey
        [description addAttribute:NSForegroundColorAttributeName
                            value:[NSColor grayColor]
                            range:NSMakeRange([[self name] length] + 1, [fileSize length] + 2)];
        
        NSMutableDictionary *mutable = [result mutableCopy];
        [mutable setObject:description forKey:@"name"];
        result = [mutable autorelease];
        
        [description release];
    }
    
    return result;
}
+ (NSSet *)keyPathsForValuesAffectingNameWithProgressAndFileSize
{
    return [NSSet setWithObjects:@"progress", @"name", @"size", nil];
}

+ (NSString *)formattedFileSize:(double)size
{
	if (size == 0) return [NSString stringWithFormat:@"0 %@", LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes")];
	NSString *suffix[] = {
		LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes"),
		LocalizedStringInConnectionKitBundle(@"KB", @"filesize: kilobytes"),
		LocalizedStringInConnectionKitBundle(@"MB", @"filesize: megabytes"),
		LocalizedStringInConnectionKitBundle(@"GB", @"filesize: gigabytes"),
		LocalizedStringInConnectionKitBundle(@"TB", @"filesize: terabytes"),
		LocalizedStringInConnectionKitBundle(@"PB", @"filesize: petabytes"),
		LocalizedStringInConnectionKitBundle(@"EB", @"filesize: exabytes")
	};
	
	int power = floor(log(size) / log(1024));
	if (power > 1)
	{
		return [NSString stringWithFormat:@"%01.02lf %@", size / pow(1024, power), suffix[power]];
	}
	else
	{
		return [NSString stringWithFormat:@"%01.0lf %@", size / pow(1024, power), suffix[power]];
	}
}

@end

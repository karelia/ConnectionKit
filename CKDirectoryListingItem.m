//
//  CKDirectoryListingItem.m
//  Connection
//
//  Created by Brian Amerige on 6/20/09.
//  Copyright 2009 Extendmac. All rights reserved.
//

#import "CKDirectoryListingItem.h"


@implementation CKDirectoryListingItem

#pragma mark -
#pragma mark Creation and Destruction
+ (CKDirectoryListingItem *)directoryListingItem
{
	return [[[CKDirectoryListingItem alloc] init] autorelease];
}

- (id)init
{
	if ((self = [super init]))
	{
		_properties = [NSMutableDictionary new];
		
		//Defaults
		[self setFileType:NSFileTypeRegular];
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[_fileType release];
	[_modificationDate release];
	[_creationDate release];
	[_fileOwnerAccountName release];
	[_groupOwnerAccountName release];
	[_filename release];
	[_symbolicLinkTarget release];
	[_size release];
	[_posixPermissions release];
	
	[_properties release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark NSObject Overrides
- (NSString *)description
{
	NSString *fileTypeString;
	if ([self isDirectory])
		fileTypeString = @"Directory";
	else if ([self isSymbolicLink])
		fileTypeString = @"Symbolic Link";
	else if ([self isCharacterSpecialFile])
		fileTypeString = @"Character Special File";
	else if ([self isBlockSpecialFile])
		fileTypeString = @"Block Special File";
	else
		fileTypeString = @"Regular File";
	return [NSString stringWithFormat:@"\"%@\" (%@) - %llu bytes", [self filename], fileTypeString, [self size]];
}

#pragma mark -
- (void)setFileType:(NSString *)fileType
{
	@synchronized (self)
	{
		if (_fileType == fileType)
			return;
		
		[_fileType release];
		_fileType = [fileType copy];
	}
}

- (BOOL)isDirectory
{
	@synchronized (self)
	{
		return (_fileType && [_fileType isEqualToString:NSFileTypeDirectory]);
	}
	return NO;
}

- (BOOL)isSymbolicLink
{
	@synchronized (self)
	{
		return (_fileType && [_fileType isEqualToString:NSFileTypeSymbolicLink]);
	}
	return NO;
}

- (BOOL)isCharacterSpecialFile
{
	@synchronized (self)
	{
		return (_fileType && [_fileType isEqualToString:NSFileTypeCharacterSpecial]);
	}
	return NO;
}

- (BOOL)isBlockSpecialFile
{
	@synchronized (self)
	{
		return (_fileType && [_fileType isEqualToString:NSFileTypeBlockSpecial]);	
	}
	return NO;
}

- (BOOL)isRegularFile
{
	@synchronized (self)
	{
		return (_fileType && [_fileType isEqualToString:NSFileTypeRegular]);	
	}
	return NO;
}

#pragma mark -
- (void)setReferenceCount:(NSInteger)referenceCount
{
	@synchronized (self)
	{
		_referenceCount = referenceCount;
	}
}

- (NSInteger)referenceCount
{
	@synchronized (self)
	{
		return _referenceCount;
	}
	return 0;
}

#pragma mark -
- (void)setModificationDate:(NSDate *)modificationDate
{
	@synchronized (self)
	{
		if (_modificationDate == modificationDate)
			return;
		
		[_modificationDate release];
		_modificationDate = [modificationDate copy];
	}
}

- (NSDate *)modificationDate
{
	@synchronized (self)
	{
		return _modificationDate;
	}
	return nil;
}

- (void)setCreationDate:(NSDate *)creationDate
{
	@synchronized (self)
	{
		if (_creationDate == creationDate)
			return;
		
		[_creationDate release];
		_creationDate = [creationDate copy];
	}
}

- (NSDate *)creationDate
{
	@synchronized (self)
	{
		return _creationDate;
	}
	return nil;
}

#pragma mark -
- (void)setSize:(NSNumber *)size
{
	@synchronized (self)
	{
		if (_size == size)
			return;
		
		[_size release];
		_size = [size copy];
	}
}

- (NSNumber *)size
{
	@synchronized (self)
	{
		return _size;
	}
	return nil;
}

#pragma mark -
- (void)setFileOwnerAccountName:(NSString *)fileOwnerAccountName
{
	@synchronized (self)
	{
		if (_fileOwnerAccountName == fileOwnerAccountName)
			return;
		
		[_fileOwnerAccountName release];
		_fileOwnerAccountName = [fileOwnerAccountName copy];
	}
}

- (NSString *)fileOwnerAccountName
{
	@synchronized (self)
	{
		return _fileOwnerAccountName;
	}
	return nil;
}

#pragma mark -
- (void)setGroupOwnerAccountName:(NSString *)groupOwnerAccountName
{
	@synchronized (self)
	{
		if (_groupOwnerAccountName == groupOwnerAccountName)
			return;
		
		[_groupOwnerAccountName release];
		_groupOwnerAccountName = [groupOwnerAccountName copy];
	}
}

- (NSString *)groupOwnerAccountName
{
	@synchronized (self)
	{
		return _groupOwnerAccountName;
	}
	return nil;
}

#pragma mark -
- (void)setFilename:(NSString *)filename
{
	@synchronized (self)
	{
		if (_filename == filename)
			return;
		
		[_filename release];
		_filename = [filename copy];
	}
}

- (NSString *)filename
{
	@synchronized (self)
	{
		return _filename;
	}
	return nil;
}

#pragma mark -
- (void)setPosixPermissions:(NSNumber *)posixPermissions
{
	if (_posixPermissions == posixPermissions)
		return;
	
	[_posixPermissions release];
	_posixPermissions = [posixPermissions copy];
}

- (NSNumber *)posixPermissions
{
	return _posixPermissions;
}

#pragma mark -
- (void)setSymbolicLinkTarget:(NSString *)symbolicLinkTarget
{
	@synchronized (self)
	{
		if (_symbolicLinkTarget == symbolicLinkTarget)
			return;
		
		[_symbolicLinkTarget release];
		_symbolicLinkTarget = [symbolicLinkTarget copy];
	}
}

- (NSString *)symbolicLinkTarget
{
	@synchronized (self)
	{
		return _symbolicLinkTarget;
	}
	return nil;
}

#pragma mark -
- (void)setProperty:(id)property forKey:(id)key
{
	@synchronized (self)
	{
		[_properties setObject:property forKey:key];
	}
}

- (id)propertyForKey:(id)key
{
	@synchronized (self)
	{
		return [_properties objectForKey:key];
	}
	return nil;
}

- (void)setObject:(id)obj forKey:(id)key
{
	[self setProperty:obj forKey:key];
}

- (id)objectForKey:(id)key
{
	return [self propertyForKey:key];
}

@end
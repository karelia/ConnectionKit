//
//  CKDirectoryListingItem.h
//  Connection
//
//  Created by Brian Amerige on 6/20/09.
//

#import <Cocoa/Cocoa.h>

@interface CKDirectoryListingItem : NSObject
{
	@private
	NSString *_fileType;
	NSInteger _referenceCount;
	NSDate *_modificationDate;
	NSDate *_creationDate;
	NSNumber *_size;
	NSString *_fileOwnerAccountName;
	NSString *_groupOwnerAccountName;
	NSString *_filename;
	NSNumber *_posixPermissions;
	NSString *_symbolicLinkTarget;
	
	NSMutableDictionary *_properties;
}

+ (CKDirectoryListingItem *)directoryListingItem;

- (void)setFileType:(NSString *)fileType;
- (BOOL)isDirectory;
- (BOOL)isSymbolicLink;
- (BOOL)isCharacterSpecialFile;
- (BOOL)isBlockSpecialFile;
- (BOOL)isRegularFile;

- (void)setReferenceCount:(NSInteger)referenceCount;
- (NSInteger)referenceCount;

- (void)setModificationDate:(NSDate *)modificationDate;
- (NSDate *)modificationDate;
- (void)setCreationDate:(NSDate *)creationDate;
- (NSDate *)creationDate;

- (void)setSize:(NSNumber *)size;
- (NSNumber *)size;

- (void)setFileOwnerAccountName:(NSString *)fileOwnerAccountName;
- (NSString *)fileOwnerAccountName;

- (void)setGroupOwnerAccountName:(NSString *)groupName;
- (NSString *)groupOwnerAccountName;

- (void)setFilename:(NSString *)filename;
- (NSString *)filename;

- (void)setPosixPermissions:(NSNumber *)posixPermissions;
- (NSNumber *)posixPermissions;

- (void)setSymbolicLinkTarget:(NSString *)symbolicLinkTarget;
- (NSString *)symbolicLinkTarget;

- (void)setProperty:(id)property forKey:(id)key;
- (id)propertyForKey:(id)key;

- (void)setObject:(id)obj forKey:(id)key;
- (id)objectForKey:(id)key;

@end
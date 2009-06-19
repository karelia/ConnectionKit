@protocol CKConnection;

@interface CKTransferRecord : NSObject
{
	BOOL _isUpload;
	NSString *_name;
	unsigned long long _sizeInBytes;
	unsigned long long _sizeInBytesWithChildren;
	unsigned long long _numberOfBytesTransferred;
	unsigned long long _numberOfBytesInLastTransferChunk;

	NSTimeInterval _lastTransferTime;
	NSTimeInterval _transferStartTime;
	NSTimeInterval _lastDirectorySpeedUpdate;
	float _speed;
	NSUInteger _progress;
	NSMutableArray *_children;
	CKTransferRecord *_parent; //not retained
	NSMutableDictionary *_properties;
	
	id <CKConnection> _connection; //not retained
	NSError *_error;
}

- (BOOL)isUpload;
- (void)setUpload:(BOOL)flag;

- (NSString *)name;
- (void)setName:(NSString *)name;

- (unsigned long long)size;
- (void)setSize:(unsigned long long)size;

- (float)speed;
- (void)setSpeed:(float)speed;	// TODO: Switch to CGFloat

- (NSError *)error;

- (id <CKConnection>)connection;
- (void)setConnection:(id <CKConnection>)connection;	// Weak ref

- (CKTransferRecord *)parent;
- (void)setParent:(CKTransferRecord *)parent;	// Weak ref


+ (id)recordWithName:(NSString *)name size:(unsigned long long)size;
- (id)initWithName:(NSString *)name size:(unsigned long long)size;
- (void)cancel:(id)sender;

- (BOOL)isDirectory;
- (unsigned long long)transferred;
- (NSInteger)progress;
- (void)setProgress:(NSInteger)progress;

- (void)addContent:(CKTransferRecord *)record;
- (NSArray *)contents;

- (BOOL)hasError;
- (BOOL)problemsTransferringCountingErrors:(int *)outErrors successes:(int *)outSuccesses;

- (CKTransferRecord *)root;
- (NSString *)path; 

- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

/* backward compatibility with NSDictionary */
- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)key;


@end

extern NSString *CKTransferRecordProgressChangedNotification;
extern NSString *CKTransferRecordTransferDidBeginNotification;
extern NSString *CKTransferRecordTransferDidFinishNotification;

@interface CKTransferRecord (Private)
- (void)setConnection:(id <CKConnection>)connection; 
- (void)setSpeed:(double)bps;
- (void)setError:(NSError *)error;
- (void)setUpload:(BOOL)flag;
- (void)setSize:(unsigned long long)size;
- (BOOL)isLeaf;
- (void)_sizeWithChildrenChangedBy:(unsigned long long)sizeDelta;
@end
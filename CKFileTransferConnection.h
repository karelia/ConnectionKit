//
//  CKFileTransferConnection.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
	CKTranscriptSent,
	CKTranscriptReceived,
	CKTranscriptData,
} CKTranscriptType;


@class NSURLRequest, CKFileTransferProtocol;
@protocol CKFileTransferDelegate, CKFileTransferProtocolClient;
    

@interface CKFileTransferConnection : NSObject
{
@private
    NSURLRequest                *_request;
    id <CKFileTransferDelegate> _delegate;;
    NSString                    *_name;
    
    // Protocol
    CKFileTransferProtocol              *_protocol;
    id <CKFileTransferProtocolClient>   _client;
    int                                 _status;
    
    // Operation queue
    id              _currentOperation;
    NSMutableArray  *_queue;
    
}

+ (CKFileTransferConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id <CKFileTransferDelegate>)delegate;
- (id)initWithRequest:(NSURLRequest *)request delegate:(id <CKFileTransferDelegate>)delegate;

- (NSURLRequest *)request;

- (void)cancel; // ceases delegate messages and forces the connection to stop as soon as possible

// Operations
- (id)uploadData:(NSData *)data toPath:(NSString *)path identifier:(id <NSObject>)identifier;

- (id)downloadContentsOfPath:(NSString *)path identifier:(id <NSObject>)identifier;

- (id)fetchContentsOfDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;

- (id)createDirectoryAtPath:(NSString *)path
withIntermediateDirectories:(BOOL)createIntermediates
                 identifier:(id <NSObject>)identifier;

- (id)removeItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;

//- (id)moveItemAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath identifier:(id <NSObject>)identifier;
//- (id)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;

@end


@interface CKFileTransferConnection (Queue)
//- (void)removeAllQueuedOperations;
@end


#pragma mark -


@interface NSURLRequest (CKFTPURLRequest)
- (NSString *)FTPDataConnectionType;    // nil signifies the usual fallback chain of connection types
@end

@interface NSURLRequest (CKSFTPURLRequest)
- (NSString *)SFTPPublicKeyPath;
@end

@interface NSMutableURLRequest (CKMutableFTPURLRequest)
- (void)setFTPDataConnectionType:(NSString *)type;
@end

@interface NSMutableURLRequest (CKMutableSFTPURLRequest)
- (void)setSFTPPublicKeyPath:(NSString *)path;
@end

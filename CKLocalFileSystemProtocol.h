//
//  CKFileConnectionProtocol.h
//  Connection
//
//  Created by Mike on 23/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFSProtocol.h"


@interface CKLocalFileSystemProtocol : CKFSProtocol
{
@private
    NSFileManager   *_fileManager;
}

@end

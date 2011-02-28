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


// For Mac OS X < 10.5.
#ifndef NSINTEGER_DEFINED
#define NSINTEGER_DEFINED
#ifdef __LP64__ || NS_BUILD_32_LIKE_64
#warning 64BIT: Inspect use of long
typedef long           NSInteger;
#warning 64BIT: Inspect use of unsigned long
typedef unsigned long  NSUInteger;
#define NSIntegerMin   LONG_MIN
#define NSIntegerMax   LONG_MAX
#define NSUIntegerMax  ULONG_MAX
#else
typedef NSInteger            NSInteger;
typedef unsigned int   NSUInteger;
#warning 64BIT: Inspect use of MAX/MIN constant; consider one of LONG_MAX/LONG_MIN/ULONG_MAX/DBL_MAX/DBL_MIN, or better yet, NSIntegerMax/Min, NSUIntegerMax, CGFLOAT_MAX/MIN
#define NSIntegerMin   INT_MIN
#warning 64BIT: Inspect use of MAX/MIN constant; consider one of LONG_MAX/LONG_MIN/ULONG_MAX/DBL_MAX/DBL_MIN, or better yet, NSIntegerMax/Min, NSUIntegerMax, CGFLOAT_MAX/MIN
#define NSIntegerMax   INT_MAX
#warning 64BIT: Inspect use of MAX/MIN constant; consider one of LONG_MAX/LONG_MIN/ULONG_MAX/DBL_MAX/DBL_MIN, or better yet, NSIntegerMax/Min, NSUIntegerMax, CGFLOAT_MAX/MIN
#define NSUIntegerMax  UINT_MAX
#endif
#endif // NSINTEGER_DEFINED


#import <Cocoa/Cocoa.h>

#import <Connection/CKConnectionProtocol.h>
#import <Connection/CKConnectionRegistry.h>
#import <Connection/CKAbstractConnection.h>
#import <Connection/CKAbstractQueueConnection.h>
#import <Connection/CKStreamBasedConnection.h>
#import <Connection/CKFTPConnection.h>
#import <Connection/CKSFTPConnection.h>
#import <Connection/CKFileConnection.h>
#import <Connection/CKDotMacConnection.h>

#import <Connection/KTLog.h>

#import <Connection/CKConnectionOpenPanel.h>
#import <Connection/RunLoopForwarder.h>
#import <Connection/InterThreadMessaging.h>
#import <Connection/NSData+Connection.h>
#import <Connection/NSObject+Connection.h>
#import <Connection/NSString+Connection.h>
#import <Connection/NSPopUpButton+Connection.h>
#import <Connection/NSTabView+Connection.h>
#import <Connection/NSNumber+Connection.h>

#import <Connection/CKTransferController.h>
#import <Connection/CKTransferRecord.h>
#import <Connection/CKTransferProgressCell.h>
#import <Connection/CKDirectoryTreeController.h>
#import <Connection/CKDirectoryNode.h>
#import <Connection/CKTableBasedBrowser.h>

#import <Connection/CKHTTPConnection.h>
#import <Connection/CKHTTPRequest.h>
#import <Connection/CKHTTPFileDownloadRequest.h>
#import <Connection/CKHTTPPutRequest.h>
#import <Connection/CKHTTPResponse.h>
#import <Connection/CKHTTPFileDownloadResponse.h>

#import <Connection/EMKeychainProxy.h>
#import <Connection/EMKeychainItem.h>
#import <Connection/CKLeopardSourceListTableColumn.h>
#import <Connection/CKBookmarkStorage.h>
#import <Connection/CKHostCategory.h>
#import <Connection/CKBonjourCategory.h>
#import <Connection/CKHost.h>
#import <Connection/CKHostCell.h>
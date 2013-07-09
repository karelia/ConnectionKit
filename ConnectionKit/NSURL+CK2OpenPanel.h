//
//  NSURL+CKRemote.h
//  ConnectionKit
//
//  Created by Paul Kim on 12/15/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or other
// materials provided with the distribution.
//
// Neither the name of Karelia Software nor the names of its contributors may be used to
// endorse or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
// SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
// WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <AppKit/AppKit.h>

@interface NSURL (CK2OpenPanel)

+ (NSURL *)ck2_loadingURL;
+ (NSURL *)ck2_errorURL;
+ (NSURL *)ck2_errorURLWithMessage:(NSString *)message;

/**
 @return    A comparator to compare the last component of URLs alphabetically.
 */
+ (NSComparator)ck2_displayComparator;

- (BOOL)ck2_isPlaceholder;

- (NSString *)ck2_displayName;
- (NSImage *)ck2_icon;
- (NSNumber *)ck2_size;
- (NSDate *)ck2_dateModified;
- (NSString *)ck2_kind;
- (BOOL)ck2_isDirectory;
- (BOOL)ck2_isPackage;
- (BOOL)ck2_isHidden;

- (NSURL *)ck2_root;
- (NSURL *)ck2_parentURL;

/**
 Will return YES if receiver and given url are the same.
 
 @return    Whether the receiver represents an ancestory directory of the given url.
 */
- (BOOL)ck2_isAncestorOfURL:(NSURL *)url;

- (NSURL *)ck2_URLByDeletingTrailingSlash;

@end

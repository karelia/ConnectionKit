//
//  CK2OpenPanel.h
//  ConnectionKit
//
//  Created by Paul Kim on 12/14/12.
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




#import <Cocoa/Cocoa.h>
#import <ConnectionKit/ConnectionKit.h>

//TODO: Handle/display errors better
//TODO: Add save panel functionality?
//TODO: Save window/view dimensions?
//TODO: Autocomplete in the path field?


@class CK2OpenPanel;
@protocol CK2OpenPanelDelegate <NSWindowDelegate>

@optional

- (void)panel:(CK2OpenPanel *)sender didChangeToDirectoryURL:(NSURL *)url;
- (BOOL)panel:(CK2OpenPanel *)sender shouldEnableURL:(NSURL *)url;
- (BOOL)panel:(CK2OpenPanel *)sender validateURL:(NSURL *)url error:(NSError **)outError;
- (void)panelSelectionDidChange:(CK2OpenPanel *)sender;

- (void)panel:(CK2OpenPanel *)sender didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
- (void)panel:(CK2OpenPanel *)sender appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;

- (void)panel:(CK2OpenPanel *)sender didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge __attribute((deprecated("implement -panel:didReceiveChallenge:completionHandler instead")));

@end


@class CK2OpenPanelController;

/**
 CK2OpenPanel is the equivalent of NSOpenPanel, but built on ConnectionKit so that it can allow you to browse
 filesystems on other machines via the protocols ConnectionKit supports. The goal of this was to emulate NSOpenPanel
 as far as it made sense. It's user and programming interfaces remain fairly close to NSOpenPanel with the following
 exceptions:

 User Interface:
 - Added a header to indicate the host. Should help in cases where multiple CK2OpenPanels are showing.
 - Since this is oriented towards selecting an existing file or directory, it does not have NSSavePanel's support
 for save operations, such as the field to enter a name for the file. Will consider adding this in if there is demand.
 - No sidebar. Besides a home directory, there are no common standard directories. It's unclear whether users would
 use this enough to keep around favorite directories on different servers.
 - A home button has been added to quickly jump to the home directory.
 - There is no search field as we cannot do anything resembling a Spotlight search over network protocols. An
 exhaustive search would be time-consuming and probably not very friendly to the server. May consider doing search
 just in the current directory, though.
 - No "arrange" pull-down. Not sure if anyone would miss this and didn't seem worth the effort.
 - No coverflow view. Not very useful (no previews) and not worth the effort.
 - The UI operates asynchronously from any operations it performs. Since these are network operations, the UI should
 not beachball while performing long operations. A progress indicator/reload button has been added and a loading
 message appears in directories whose contents are being retrieved.
 - No preview or application icons (a generic app icon is used). It's a bit resource heavy and server-unfriendly
 downloading application icons. Previews for other files would end up just downloading files outright.
 - No QuickLook. See above about previews.
 - Does not support drag and drop. Doesn't make sense to have the open panel navigate to a file on the server based
 on a locally dropped file.

 API:
 - No API's related to saving files (name field, expansion state, hide extension).
 - -setDirectoryURL: can also take a completion block, since the operation is asynchronous.

 Despite all of the above, CK2OpenPanel should be a near-drop-in replacement for NSOpenPanel in terms of code usage
 and user experience. The emulation of NSOpenPanel's behavior goes fairly deep and you may be
 surprised by the features supported.
 */
@interface CK2OpenPanel : NSPanel
{
    CK2OpenPanelController      *_viewController;
    NSString                    *_title;
    NSString                    *_prompt;
    NSString                    *_message;
    BOOL                        _canChooseFiles;
    BOOL                        _canChooseDirectories;
    BOOL                        _allowsMultipleSelection;
    BOOL                        _showsHiddenFiles;
    BOOL                        _treatsFilePackagesAsDirectories;
    BOOL                        _canCreateDirectories;
    NSArray                     *_allowedFileTypes;
    
    void                        (^_completionBlock)(NSInteger result);
}

@property (readwrite, copy) NSString    *title;
@property (readwrite, copy) NSString    *prompt;
@property (readwrite, copy) NSString    *message;
@property (readwrite, retain) NSView    *accessoryView;
@property (readwrite, assign) BOOL      canChooseFiles;
@property (readwrite, assign) BOOL      canChooseDirectories;
@property (readwrite, assign) BOOL      allowsMultipleSelection;
@property (readwrite, assign) BOOL      showsHiddenFiles;
@property (readwrite, assign) BOOL      treatsFilePackagesAsDirectories;
@property (readwrite, assign) BOOL      canCreateDirectories;
@property (readwrite, copy) NSArray     *allowedFileTypes;
@property (readwrite, retain, nonatomic) NSURL       *directoryURL;

@property (readonly, retain) NSURL        *URL;
@property (readonly, copy) NSArray      *URLs;



+ (CK2OpenPanel *)openPanel;

@property(assign) id <CK2OpenPanelDelegate> delegate;

/**
 The completion block will not be called until the given URL's contents are fully loaded. That way, if you show the
 panel in the completion block, nothing will be "in progress". You can still show the panel beforehand but much of
 the UI will be disabled until the URL is loaded. The UI will still be responsive in that you'll see progress
 indicators spinning and you can still cancel the panel.
 
 The completion block is called on the main thread, and as a nicety,
 deliberately *avoids* using a dispatch queue to do so, so you can call
 `-runModal` from within it if desired (see the `-runModal` docs for details).

 Note that directoryURL immediately reflects the URL this method was called with but may change when the operation
 is complete as the server may resolve the URL to something else. It's best to not rely on the directoryURL until
 the completion block has fired.

 Most commonly, we expect you'll want to show the user's home directory. To get that URL, consult CK2FileManager like so:
  NSURL *homeDir = [CK2FileManager URLWithPath:@"" isDirectory:YES hostURL:[NSURL URLWithString:@"sftp://example.com"]];
 
 @param directoryURL        The URL of the host/directory to connect to.
 @param block               The completion block that is called when the operation is complete.
*/
- (void)setDirectoryURL:(NSURL *)directoryURL completionHandler:(void (^)(NSError *error))block;

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler;
- (void)beginWithCompletionHandler:(void (^)(NSInteger result))handler;

/**
 Displays the panel and begins its event loop with the current working (or last selected) directory as the default starting point.
 
 @return `NSFileHandlingPanelOKButton` (if the user clicks the OK button) or `NSFileHandlingPanelCancelButton` (if the user clicks the Cancel button).
 
 This method invokes `-[NSApplication runModalForWindow:` with `self` as the
 argument.
 
 You must **NOT** run an open panel modally from the main dispatch
 queue. Doing so will block the queue, preventing important internal callbacks
 from arriving, including from ConnectionKit itself, and the springy scrolling
 behaviour introduced in 10.7+.
 
 Instead, call as part of regular runloop activity, such as directly from a user-
 generated event, or deferred execution using something like
 `-performSelector:afterDelay:…`
 */
- (NSInteger)runModal;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

- (void)validateVisibleColumns;

@end

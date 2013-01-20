//
//  CKRemoteViewController.m
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


//NOTES:
// - Besides the normal UI stuff which must be done in the main thread, the URL cache must also only be modified in the
//   main thread. This is to prevent a case where NSBrowser or NSOutlineView query for the children of an URL first for
//   the number of children, then query again for the actual children. In this case, if the URL cache is updated in
//   between these two calls, those UI classes can end up asking for an invalid index.
// - Because most things should only be modified in the main thread, you may not see the results until the next
//   run loop cycle. Since we're using GCD, it's a queue so you can at least rely on order of operations corresponding
//   to the order you queued things up.
// - The previous point is exploited to avoid race conditions. Otherwise, a semaphore (wait/signal) would have to be
//   used in those cases.
// - Don't do too much stuff in the file manager completion blocks. That is holding up the file manager queue and
//   can result in deadlock if you end up calling back into the file manager.


#import "CK2OpenPanelController.h"
#import "CK2OpenPanel.h"
#import "CK2FileCell.h"
#import "NSURL+CK2OpenPanel.h"
#import "CK2OpenPanelViewController.h"
#import "CK2OpenPanelIconViewController.h"
#import "CK2OpenPanelListViewController.h"
#import "CK2OpenPanelColumnViewController.h"
#import "CK2PathControl.h"
#import <Connection/CK2FileManager.h>

#define MIN_PROMPT_BUTTON_WIDTH         82
#define PROMPT_BUTTON_RIGHT_MARGIN      18

#define HISTORY_DIRECTORY_URL_KEY           @"directoryURL"
#define HISTORY_DIRECTORY_VIEW_INDEX_KEY    @"viewIndex"

#define ICON_VIEW_IDENTIFIER                @"icon"
#define LIST_VIEW_IDENTIFIER                @"list"
#define COLUMN_VIEW_IDENTIFIER              @"column"
#define BLANK_VIEW_IDENTIFIER               @"blank"

#define CK2OpenPanelDidLoadURL              @"CK2OpenPanelDidLoadURL"
#define CK2ErrorNotificationKey             @"error"
#define CK2URLNotificationKey               @"url"

@interface CK2OpenPanelController ()

@property (readwrite, copy) NSURL       *directoryURL;

@end

@implementation CK2OpenPanelController

@synthesize openPanel = _openPanel;
@synthesize directoryURL = _directoryURL;
@synthesize URLs = _urls;
@synthesize homeURL = _home;

- (id)initWithPanel:(CK2OpenPanel *)panel
{
    NSBundle        *bundle;
    
    bundle = [NSBundle bundleForClass:[self class]];
    
    if ((self = [super initWithNibName:@"CK2OpenPanel" bundle:bundle]) != nil)
    {
        _openPanel = panel;
        _urlCache = [[NSMutableDictionary alloc] init];
        _runningOperations = [[NSMutableDictionary alloc] init];

        _historyManager = [[NSUndoManager alloc] init];
        
        _fileManager = [[CK2FileManager alloc] init];
        [_fileManager setDelegate:self];
        
        [_openPanel addObserver:self forKeyPath:@"prompt" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canChooseFiles" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canChooseDirectories" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"allowsMultipleSelection" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"showsHiddenFiles" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"treatsFilePackagesAsDirectories" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canCreateDirectories" options:NSKeyValueObservingOptionNew context:NULL];        
    }
    
    return self;
}

- (void)dealloc
{
    for (id operation in [_runningOperations allValues])
    {
        [_fileManager cancelOperation:operation];
    }
    
    if (_currentBootstrapOperation != nil)
    {
        [_fileManager cancelOperation:_currentBootstrapOperation];
        [_currentBootstrapOperation release];
    }
    
    [_fileManager release];
    
    [_openPanel removeObserver:self forKeyPath:@"prompt"];
    [_openPanel removeObserver:self forKeyPath:@"canChooseFiles"];
    [_openPanel removeObserver:self forKeyPath:@"canChooseDirectories"];
    [_openPanel removeObserver:self forKeyPath:@"allowsMultipleSelection"];
    [_openPanel removeObserver:self forKeyPath:@"showsHiddenFiles"];
    [_openPanel removeObserver:self forKeyPath:@"treatsFilePackagesAsDirectories"];
    [_openPanel removeObserver:self forKeyPath:@"canCreateDirectories"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:_openPanel];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:_openPanel];

    [_urls release];
    [_urlCache release];
    [_historyManager release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    NSTabViewItem       *item;
    
    [self validateHistoryButtons];
    [self validateOKButton];
    [self validateProgressIndicator];
   
    //PENDING: should store last view in prefs and restore it here
    item = [_tabView tabViewItemAtIndex:[_tabView indexOfTabViewItemWithIdentifier:COLUMN_VIEW_IDENTIFIER]];
    [_tabView selectTabViewItem:item];
    [_openPanel makeFirstResponder:[item initialFirstResponder]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqual:@"prompt"])
    {
        NSRect  rect1, rect2, superBounds;
        
        [_okButton setTitle:[_openPanel prompt]];
        superBounds = [[_okButton superview] bounds];
        
        [_okButton sizeToFit];
        rect1 = [_okButton frame];
        rect1.size.width = MAX(MIN_PROMPT_BUTTON_WIDTH, NSWidth(rect1));
        rect1.origin.x = NSMaxX(superBounds) - PROMPT_BUTTON_RIGHT_MARGIN - NSWidth(rect1);
        [_okButton setFrame:rect1];
        
        rect2 = [_cancelButton frame];
        rect2.origin.x = NSMinX(rect1) - NSWidth(rect2);
        [_cancelButton setFrame:rect2];
    }
    else if ([keyPath isEqual:@"canChooseFiles"] || [keyPath isEqual:@"canChooseDirectories"] ||
             [keyPath isEqual:@"showsHiddenFiles"] || [keyPath isEqual:@"treatsFilePackagesAsDirectories"])
    {
        [[_browserController view] setNeedsDisplay:YES];
        [[_listViewController view] setNeedsDisplay:YES];
        [_iconViewController reload];
        [self validateOKButton];
    }
    else if ([keyPath isEqual:@"canCreateDirectories"])
    {
        if ([_openPanel canCreateDirectories])
        {
            [_newFolderButton setHidden:NO];
        }
        else
        {
            [_newFolderButton setHidden:YES];
        }
    }
    else if ([keyPath isEqual:@"allowsMultipleSelection"])
    {
        [_iconViewController setAllowsMutipleSelection:[_openPanel allowsMultipleSelection]];
        [_listViewController setAllowsMutipleSelection:[_openPanel allowsMultipleSelection]];
        [_browserController setAllowsMutipleSelection:[_openPanel allowsMultipleSelection]];
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)resetSession
{
    for (id operation in [_runningOperations allValues])
    {
        [_fileManager cancelOperation:operation];
    }
    [_runningOperations removeAllObjects];
    
    if (_currentBootstrapOperation != nil)
    {
        [_fileManager cancelOperation:_currentBootstrapOperation];
        [_currentBootstrapOperation release];
        _currentBootstrapOperation = nil;
    }

    [_urlCache removeAllObjects];
    [_runningOperations removeAllObjects];
    [_historyManager removeAllActions];

    [self validateViews];
}

- (NSURL *)URL
{
    if ([_urls count] > 0)
    {
        return [_urls objectAtIndex:0];
    }
    return nil;
}

- (void)setURL:(NSURL *)URL
{
    [_urls release];
    if (URL != nil)
    {
        _urls = [@[ URL ] retain];
    }
}

// This pre-loads all the URLs up to the given one. Used in the bootstrapping process. This method
// should NOT be called from the main thread as it will deadlock. It is meant to block until all the URLs are loaded.
- (BOOL)loadURLsUpToURL:(NSURL *)url error:(NSError **)error
{
    __block NSError         *localError;
    dispatch_group_t        dispatchGroup;
    id                      observer;
    NSMutableArray          *observedURLs;
    
    localError = nil;

    dispatchGroup = dispatch_group_create();
    
    observedURLs = [NSMutableArray array];
    
    // We can't just thread a completion block through to find out when an URL is loaded. The problem is that the
    // URL-load may already have been triggered. Instead, we set up a notification to be posted so that we can react
    // to it even if we didn't trigger the initial load operation.
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:CK2OpenPanelDidLoadURL object:self queue:nil usingBlock:
                ^ (NSNotification *notification)
                {
                    NSURL       *loadedURL;
                    
                    loadedURL = [[notification userInfo] objectForKey:CK2URLNotificationKey];
                    
                    if ([observedURLs containsObject:loadedURL])
                    {
                        NSError    *blockError;
                                        
                        blockError = [[notification userInfo] objectForKey:CK2ErrorNotificationKey];
                        if (blockError != nil)
                        {
                            localError = [blockError retain];
                        }
                        dispatch_group_leave(dispatchGroup);
                    }
                }];

    // Have to be synchronous here as we want all the "enters" to occur before we do the "wait" below
    dispatch_sync(dispatch_get_main_queue(),
    ^{
        [url enumerateFromRoot:
         ^(NSURL *blockURL, BOOL *stop)
         {
             NSArray    *children;

             //PENDING: Is completion block called if an operation is cancelled?
             children = [self childrenForURL:blockURL];
             
             if (([children count] == 1) && [[children objectAtIndex:0] isPlaceholder])
             {
                 // URL contents haven't been loaded yet. We will get a notification for this later via the block above.
                 dispatch_group_enter(dispatchGroup);
                 [observedURLs addObject:blockURL];
             }
         }];
    });
    
    dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
    dispatch_release(dispatchGroup);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    [localError autorelease];
    if (error != NULL)
    {
        *error = localError;
    }
    
    return (localError == nil);
}

// Called by the open panel. The completion block will not be called until the given URL and all URLs up to it are
// loaded.
- (void)changeDirectory:(NSURL *)directoryURL completionBlock:(void (^)(NSError *error))block
{
    if (![[directoryURL root] isEqual:[[self URL] root]])
    {
        [self loadRoot:directoryURL completionBlock:block];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            NSError *error;
            BOOL    success;
            
            //PENDING: blank out/disable UI as with loading root?
            error = nil;
            success = [self loadURLsUpToURL:directoryURL error:&error];
            
            dispatch_async(dispatch_get_main_queue(),
            ^{
                if (success)
                {
                    [self setURLs:@[ directoryURL ] updateDirectory:YES sender:_openPanel];
                }
                
                if (block != NULL)
                {
                    block(error);
                }
            });
        });
    }
}


// This is the "bootstrap" method which loads up the initial URL, including the directory entries of its ancestors.
// This is different than just loading up any directory in that we need to do an initial query to resolve the URL
// in case it's a relative path (usually to the user's home directory).
// During this time, the UI is disabled and a progress indicator is shown. The completion block is not called until
// everything is fully loaded.
- (void)loadRoot:(NSURL *)rootURL completionBlock:(void (^)(NSError *error))block
{
    NSMutableArray          *children;
    __block NSURL           *resolvedURL;
    
    children = [NSMutableArray array];
    
    //PENDING: compare url
    if (_currentBootstrapOperation != nil)
    {
        [_fileManager cancelOperation:_currentBootstrapOperation];
        [_currentBootstrapOperation release];
    }
    
    resolvedURL = nil;
    
    _currentBootstrapOperation = [_fileManager enumerateContentsOfURL:rootURL includingPropertiesForKeys:@[ NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLLocalizedNameKey ] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants usingBlock:
     ^ (NSURL *blockURL)
     {
         if (resolvedURL == nil)
         {
             // The first url returned is the rootURL properly resolved (in case the URL is relative to the user's home
             // directory, for instance).
             resolvedURL = [blockURL retain];
         }
         else
         {
             [children addObject:blockURL];
         }
     }
    completionHandler:
     ^(NSError *blockError)
     {
         // Get this off of the file manager's queue so that we don't deadlock if we call back into it.
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
         ^{
             __block NSError *tempError;
             
#warning Added delay for testing. Remove before committing
//             sleep(1);
             
             tempError = nil;
             if (blockError != nil)
             {
                 [children addObject:[NSURL errorURL]];                 
                 tempError = [blockError retain];
             }
             else
             {
                 dispatch_async(dispatch_get_main_queue(),
                 ^{
                     [_urlCache setObject:children forKey:resolvedURL];
                     [self urlDidLoad:resolvedURL];
                 });
                 
                 if (![resolvedURL isEqual:rootURL])
                 {
                     NSString    *resolvedPath;
                     NSRange     range;
                     
                     // If the resolved URL is different than the original one, then we assume the URL was relative and
                     // we try and derive the user's "home" directory from that.
                     resolvedPath = [resolvedURL path];
                     range = [resolvedPath rangeOfString:[rootURL path] options:NSAnchoredSearch | NSBackwardsSearch];
                     
                     if (range.location != NSNotFound)
                     {
                         resolvedPath = [resolvedPath substringToIndex:range.location];
                         [self setHomeURL:[NSURL URLWithString:resolvedPath relativeToURL:[resolvedURL root]]];
                     }
                 }
                 
                 [self loadURLsUpToURL:resolvedURL error:&tempError];                 
             }
             
             dispatch_async(dispatch_get_main_queue(),
             ^{
                 _currentBootstrapOperation = nil;
                                
                 if (tempError == nil)
                 {
                     [self setURLs:@[ resolvedURL ] updateDirectory:YES];
                 }
                 [self validateViews];
                                
                 if (block != NULL)
                 {
                     block([tempError autorelease]);
                 }
             });
             
             [resolvedURL autorelease];
         });
     }];
    
    [_currentBootstrapOperation retain];
    
    [_hostField setStringValue:[rootURL host]];
    [self validateViews];
}


- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)flag
{
    [self setURLs:urls updateDirectory:flag sender:nil];
}

- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)flag sender:(id)sender
{
    CK2OpenPanelViewController  *currentController;
    
    [self setURLs:urls];
    [self validateOKButton];
    
    if (flag)
    {
        NSURL       *directoryURL;

        directoryURL = [urls objectAtIndex:0];
        if (![directoryURL canHazChildren])
        {
            directoryURL = [directoryURL URLByDeletingLastPathComponent];
        }
        
        if (![directoryURL isEqual:[self directoryURL]])
        {
            [self setDirectoryURL:directoryURL];
            
            if (sender != _pathControl)
            {
                [_pathControl setURL:directoryURL];
            }
            
            if ([[_openPanel delegate] respondsToSelector:@selector(panel:didChangeToDirectoryURL:)])
            {
                [[_openPanel delegate] panel:_openPanel didChangeToDirectoryURL:directoryURL];
            }
        }
    }
    
    currentController = [self viewControllerForIdentifier:[[_tabView selectedTabViewItem] identifier]];
    if ((sender != currentController) || (![currentController hasFixedRoot] && flag))
    {
        if (flag)
        {
            [currentController reload];
        }
        [currentController update];
    }
        
    if ([[_openPanel delegate] respondsToSelector:@selector(panelSelectionDidChange:)])
    {
        [[_openPanel delegate] panelSelectionDidChange:_openPanel];
    }
}

- (NSArray *)childrenForURL:(NSURL *)url
{
    id      children;
        
    children = nil;
    if ((url != nil) && [url canHazChildren])
    {
        children = [_urlCache objectForKey:url];
        
        if (children == nil)
        {
            NSDirectoryEnumerationOptions   options;
            id                              operation;
            NSArray                         *blockChildren;
            
            // Placeholder while children are being fetched
            children = @[ [NSURL loadingURL] ];
            
            blockChildren = children;
            
            [_urlCache setObject:blockChildren forKey:url];
//            [self urlDidLoad:url];
            
            if ([_runningOperations objectForKey:url] == nil)
            {                
                options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
                
                if (![_openPanel showsHiddenFiles])
                {
                    options |= NSDirectoryEnumerationSkipsHiddenFiles;
                }
                if (![_openPanel treatsFilePackagesAsDirectories])
                {
                    options |= NSDirectoryEnumerationSkipsPackageDescendants;
                }
                                                
                operation = [_fileManager contentsOfDirectoryAtURL:url
                                        includingPropertiesForKeys:@[ NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLLocalizedNameKey ]
                                                           options:options
                completionHandler:
                ^(NSArray *contents, NSError *blockError)
                {
                    id             value;
                    
                    value = contents;
                    if (value == nil)
                    {
                        if (blockError != nil)
                        {
                            value = @[ [NSURL errorURL] ];
                        }
                        else
                        {
                            // We use NSNull as an indicator that the URL has no children to differentiate it from not
                            // being in the cache at all.
                            value = [NSNull null];
                        }
                    }
                    
                    dispatch_async(dispatch_get_main_queue(),
                    ^{
                        NSNotification      *notification;
                        NSMutableDictionary *userInfo;
                        
                        [_urlCache setObject:value forKey:url];

                        [_runningOperations removeObjectForKey:url];
                        
                        [self validateProgressIndicator];
                        [self urlDidLoad:url];
                        
                        userInfo = [NSMutableDictionary dictionaryWithObject:url forKey:CK2URLNotificationKey];
                        
                        if (blockError != nil)
                        {
                            [userInfo setObject:blockError forKey:CK2ErrorNotificationKey];
                        }
                        
                        notification = [NSNotification notificationWithName:CK2OpenPanelDidLoadURL object:self
                                                                   userInfo:userInfo];
                        [[NSNotificationCenter defaultCenter] postNotification:notification];
                    });
                }];

                // There shouldn't be a race condition with the block above since this should be on the main thread and
                // the above block won't run on the main thread until this code completes and returns to the run loop.
                [_runningOperations setObject:operation forKey:url];

                [self validateProgressIndicator];
            }
        }
        else if ([children isEqual:[NSNull null]])
        {
            children = nil;
        }
    }
    return children;
}

- (BOOL)isURLValid:(NSURL *)url
{
    if (![url isPlaceholder])
    {
        id <CK2OpenPanelDelegate>  delegate;
        BOOL                            delegateValid;
        
        delegate = [_openPanel delegate];
        
        delegateValid = (![delegate respondsToSelector:@selector(panel:shouldEnableURL:)] || [delegate panel:_openPanel shouldEnableURL:url]);
        
        if ([url canHazChildren])
        {
            return [_openPanel canChooseDirectories] && delegateValid;
        }
        else
        {
            return [_openPanel canChooseFiles] && delegateValid;
        }
    }
    return NO;
}

- (void)urlDidLoad:(NSURL *)url
{
    [[self viewControllerForIdentifier:[[_tabView selectedTabViewItem] identifier]] urlDidLoad:url];
}

- (CK2OpenPanelViewController *)viewControllerForIdentifier:(NSString *)identifier
{
    if ([identifier isEqual:COLUMN_VIEW_IDENTIFIER])
    {
        return _browserController;
    }
    else if ([identifier isEqual:LIST_VIEW_IDENTIFIER])
    {
        return _listViewController;
    }
    else if ([identifier isEqual:ICON_VIEW_IDENTIFIER])
    {
        return _iconViewController;
    }
    return nil;
}

- (void)validateViews
{
    BOOL    enable;
    
    enable = (_currentBootstrapOperation == nil);
    
    [_viewPicker setEnabled:enable];
    [_homeButton setEnabled:enable];
    
    if (!enable)
    {
        if (_lastTab == nil)
        {
            _lastTab = [_tabView selectedTabViewItem];
        }
        
        [_tabView selectTabViewItemWithIdentifier:BLANK_VIEW_IDENTIFIER];
    }
    else
    {
        if (_lastTab == nil)
        {
            _lastTab = [_tabView tabViewItemAtIndex:[_tabView indexOfTabViewItemWithIdentifier:COLUMN_VIEW_IDENTIFIER]];
        }
        [_tabView selectTabViewItem:_lastTab];
        _lastTab = nil;
    }
    
    [self validateHistoryButtons];
    [self validateOKButton];
    [self validateProgressIndicator];
    [self validateHomeButton];
}

- (void)validateProgressIndicator
{
    if (([_runningOperations count] == 0) && (_currentBootstrapOperation == nil))
    {
        [_progressIndicator stopAnimation:self];
        [_progressIndicator setHidden:YES];
    }
    else
    {
        [_progressIndicator startAnimation:self];
        [_progressIndicator setHidden:NO];
    }
}

- (void)validateHomeButton
{
    [_homeButton setEnabled:([self homeURL] != nil)];
}

- (void)validateOKButton
{
    BOOL    isValid;
    
    isValid = NO;
    if (_currentBootstrapOperation == nil)
    {
        isValid = YES;
        for (NSURL *url in [self URLs])
        {
            if (![self isURLValid:url])
            {
                isValid = NO;
                break;
            }
        }
    }
    
    [_okButton setEnabled:isValid];
}

- (IBAction)ok:(id)sender
{
    [_openPanel ok:sender];
}

- (IBAction)cancel:(id)sender
{
    [self setURL:nil];
    [_openPanel cancel:sender];
}

- (IBAction)newFolder:(id)sender
{
    //PENDING:
}

- (void)validateHistoryButtons
{
    [_historyButtons setEnabled:((_currentBootstrapOperation == nil) && ([_historyManager canUndo])) forSegment:0];
    [_historyButtons setEnabled:((_currentBootstrapOperation == nil) && ([_historyManager canRedo])) forSegment:1];
}

- (IBAction)changeHistory:(id)sender
{
    NSInteger       selectedIndex;
    
    selectedIndex = [_historyButtons selectedSegment];
    switch (selectedIndex)
    {
        case 0:
            [self back:sender];
            break;
        case 1:
            [self forward:sender];
            break;
    }
}

- (IBAction)back:(id)sender
{
    [_historyManager undo];
    [self validateHistoryButtons];
}

- (IBAction)forward:(id)sender
{
    [_historyManager redo];
    [self validateHistoryButtons];
}

- (void)changeView:(NSDictionary *)dict
{
    [self addToHistory];

    [self setURLs:@[ [dict objectForKey:HISTORY_DIRECTORY_URL_KEY] ] updateDirectory:YES];
    [_tabView selectTabViewItemAtIndex:[[dict objectForKey:HISTORY_DIRECTORY_VIEW_INDEX_KEY] unsignedIntegerValue]];
}

- (void)addToHistory
{
    [_historyManager registerUndoWithTarget:self selector:@selector(changeView:)
                                  object:@{ HISTORY_DIRECTORY_URL_KEY : [_openPanel directoryURL],
       HISTORY_DIRECTORY_VIEW_INDEX_KEY : [NSNumber numberWithUnsignedInteger:[_tabView indexOfTabViewItem:[_tabView selectedTabViewItem]]] }];
    
    [self validateHistoryButtons];
}

- (IBAction)home:(id)sender
{
    NSURL   *homeURL;
    
    homeURL = [self homeURL];
    
    if (homeURL != nil)
    {
        [self setURLs:@[ homeURL ] updateDirectory:YES];
    }
}

- (IBAction)pathControlItemSelected:(id)sender
{
    NSURL       *url;
    
    url = [_pathControl URL];
    
    if (![url isEqual:[_openPanel directoryURL]])
    {
        [self addToHistory];
        [self setURLs:@[ url ] updateDirectory:YES sender:_pathControl];
    }
}

#pragma mark NSPathControlDelegate

- (BOOL)pathControl:(NSPathControl *)pathControl shouldDragPathComponentCell:(NSPathComponentCell *)pathComponentCell withPasteboard:(NSPasteboard *)pasteboard
{
    return NO;
}


#pragma mark NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    CK2OpenPanelViewController  *viewController;
    
    viewController = [self viewControllerForIdentifier:[tabViewItem identifier]];
    [viewController reload];
    [viewController update];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    [_openPanel makeFirstResponder:[tabViewItem initialFirstResponder]];
}

#pragma mark CK2FileManagerDelegate

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    id <CK2OpenPanelDelegate>        delegate;
    
    delegate = [[self openPanel] delegate];
    
    if ([delegate respondsToSelector:@selector(panel:didReceiveAuthenticationChallenge:)])
    {
        [delegate panel:[self openPanel] didReceiveAuthenticationChallenge:challenge];
    }
}

@end

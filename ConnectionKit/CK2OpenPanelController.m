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


#import "CK2OpenPanelController.h"
#import "CK2OpenPanel.h"
#import "CK2FileCell.h"
#import "NSURL+CK2OpenPanel.h"
#import "CK2OpenPanelViewController.h"
#import "CK2OpenPanelIconViewController.h"
#import "CK2OpenPanelListViewController.h"
#import "CK2OpenPanelColumnViewController.h"
#import "CK2PathControl.h"
#import "CK2NewFolderWindowController.h"
#import "CK2IconView.h"
#import "CK2PathFieldWindowController.h"
#import <ConnectionKit/CK2FileManager.h>

#define DEFAULT_OPERATION_TIMEOUT       20

#define MIN_PROMPT_BUTTON_WIDTH         82
#define PROMPT_BUTTON_RIGHT_MARGIN      18
#define MESSAGE_SIDE_MARGIN             16
#define MESSAGE_HEIGHT                  24

#define HISTORY_DIRECTORY_URL_KEY           @"directoryURL"
#define HISTORY_DIRECTORY_VIEW_INDEX_KEY    @"viewIndex"

#define ICON_VIEW_IDENTIFIER                @"icon"
#define LIST_VIEW_IDENTIFIER                @"list"
#define COLUMN_VIEW_IDENTIFIER              @"column"
#define BLANK_VIEW_IDENTIFIER               @"blank"

#define CK2OpenPanelLastViewPrefKey         @"CK2NavPanelFileLastListModeForOpenModeKey"

@interface CK2OpenPanelController ()

@property (readwrite, retain) NSURL       *directoryURL;

@end

@implementation CK2OpenPanelController

@synthesize openPanel = _openPanel;
@synthesize directoryURL = _directoryURL;
@synthesize URLs = _urls;
@synthesize homeURL = _homeURL;

@synthesize fileManager = _fileManager;

#pragma mark Lifecycle

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
        
        _fileManager = [[CK2FileManager fileManagerWithDelegate:self delegateQueue:[NSOperationQueue mainQueue]] retain];
        
        [_openPanel addObserver:self forKeyPath:@"prompt" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"message" options:NSKeyValueObservingOptionOld context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canChooseFiles" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canChooseDirectories" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"allowsMultipleSelection" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"showsHiddenFiles" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"treatsFilePackagesAsDirectories" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"allowedFileTypes" options:NSKeyValueObservingOptionNew context:NULL];
        [_openPanel addObserver:self forKeyPath:@"canCreateDirectories" options:NSKeyValueObservingOptionNew context:NULL];
    }
    
    return self;
}

- (void)close
{
    [_openPanel removeObserver:self forKeyPath:@"prompt"];
    [_openPanel removeObserver:self forKeyPath:@"message"];
    [_openPanel removeObserver:self forKeyPath:@"canChooseFiles"];
    [_openPanel removeObserver:self forKeyPath:@"canChooseDirectories"];
    [_openPanel removeObserver:self forKeyPath:@"allowsMultipleSelection"];
    [_openPanel removeObserver:self forKeyPath:@"showsHiddenFiles"];
    [_openPanel removeObserver:self forKeyPath:@"treatsFilePackagesAsDirectories"];
    [_openPanel removeObserver:self forKeyPath:@"allowedFileTypes"];
    [_openPanel removeObserver:self forKeyPath:@"canCreateDirectories"];
    
    if (_openPanel)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:_openPanel];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:_openPanel];
    }
    
    _openPanel = nil;
}

- (void)dealloc
{
    [_initialAccessoryView release];
    for (CK2FileOperation *operation in [_runningOperations allValues])
    {
        [operation cancel];
    }
    
    if (_currentLoadingOperation != nil)
    {
        [_currentLoadingOperation cancel];
        [_currentLoadingOperation release];
    }
    
    [self close];   // just to be sure

    [_directoryURL release];
    [_urls release];
    [_homeURL release];
    [_urlCache release];
    [_runningOperations release];
    [_fileManager release];
    [_historyManager release];
    [_pathFieldController release];
    
    [super dealloc];
}

- (void)awakeFromNib
{
    NSTabViewItem       *item;
    id                  value;
   
    _initialAccessoryView = [[_accessoryContainer contentView] retain];
    
    [_hostField setStringValue:@""];
    [self validateHistoryButtons];
    [self validateOKButton];
    [self validateProgressIndicator];
   
    value = [[NSUserDefaults standardUserDefaults] stringForKey:CK2OpenPanelLastViewPrefKey];
    if (value == nil)
    {
        // If not set, use the global default used by NSOpenPanel
        value = [[NSUserDefaults standardUserDefaults] stringForKey:@"NSNavPanelFileLastListModeForOpenModeKey"];

        switch ([value integerValue])
        {
            case 1:
                value = COLUMN_VIEW_IDENTIFIER;
                break;
            case 2:
                value = LIST_VIEW_IDENTIFIER;
                break;
            case 3:
                value = ICON_VIEW_IDENTIFIER;
                break;
            default:
                value = ICON_VIEW_IDENTIFIER;
        }
    }
    
    item = [_tabView tabViewItemAtIndex:[_tabView indexOfTabViewItemWithIdentifier:value]];
    
    [_tabView selectTabViewItem:item];
    [_viewPicker setSelectedSegment:[_tabView indexOfTabViewItem:item]];
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
    else if ([keyPath isEqual:@"message"])
    {
        id          oldMessage;
        NSString    *message;
        CGFloat     height;
        NSRect      rect, bounds;
        
        oldMessage = [change objectForKey:NSKeyValueChangeOldKey];
        oldMessage = oldMessage == [NSNull null] ? nil : oldMessage;
        message = [_openPanel message];

        if ([message length] > 0)
        {
            [_messageLabel setStringValue:message];
        }
        
        bounds = [[self view] bounds];
        height = 0.0;
        
        if (([oldMessage length] == 0) && ([message length] > 0))
        {
            height = MESSAGE_HEIGHT;
        }
        else if (([oldMessage length] > 0) && ([message length] == 0))
        {
            height = -MESSAGE_HEIGHT;
        }
        
        if (height != 0.0)
        {
            NSUInteger  buttonMask, middleMask;
            
            rect = [[self view] frame];
            rect.size.height += height;
            
            buttonMask = [_buttonSection autoresizingMask];
            [_buttonSection setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
            middleMask = [_middleSection autoresizingMask];
            [_middleSection setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
            
            rect = [_openPanel frameRectForContentRect:rect];
            [_openPanel setFrame:rect display:YES];
            
            [_buttonSection setAutoresizingMask:buttonMask];
            [_middleSection setAutoresizingMask:middleMask];

            if ([_messageLabel superview] != [self view])
            {
                rect = [_messageLabel frame];
                rect.origin.x = NSMinX(bounds) + MESSAGE_SIDE_MARGIN;
                rect.origin.y = NSMaxY([_buttonSection frame]);
                rect.size.width = NSWidth(bounds) - 2 * MESSAGE_SIDE_MARGIN;
                [_messageLabel setFrame:rect];
                [[self view] addSubview:_messageLabel];
            }
            else
            {
                [_messageLabel removeFromSuperview];
            }
        }
    }
    else if ([keyPath isEqual:@"canChooseFiles"] || [keyPath isEqual:@"canChooseDirectories"] ||
             [keyPath isEqual:@"showsHiddenFiles"] || [keyPath isEqual:@"treatsFilePackagesAsDirectories"] ||
             [keyPath isEqual:@"allowedFileTypes"])
    {
        [self validateVisibleColumns];
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

- (NSArray *)fileProperties
{
    return @[ NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLLocalizedNameKey, NSURLIsSymbolicLinkKey, CK2URLSymbolicLinkDestinationKey, NSURLIsPackageKey, NSURLIsHiddenKey, NSURLEffectiveIconKey, NSURLParentDirectoryURLKey ];
}

- (NSView *)accessoryView
{
    NSView  *view;
    
    view = [_accessoryContainer contentView];
    
    if (view == _initialAccessoryView)
    {
        return nil;
    }
    return view;
}

- (void)setAccessoryView:(NSView *)accessoryView
{
    NSRect  rect;
    CGFloat height;
    NSUInteger  mask;
    
    // Save off the mask and tweak it. We want the middle section to have different resizing behavior while we
    // resize the window
    mask = [_middleSection autoresizingMask];
    [_middleSection setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];

    if (accessoryView != nil)
    {
        NSRect      accessoryFrame, containerFrame;

        height = 0.0;
        if ([_accessoryContainer superview] == [self view])
        {
            height = NSHeight([[_accessoryContainer contentView] frame]);
        }
        
        accessoryFrame = [accessoryView frame];

        // Remove the accessory container while we muck around with window dimensions and such. We want to preserve the
        // accessory view's original size. Also, no need to retain because it's a top-level object in the xib.
        [_accessoryContainer removeFromSuperview];
        
        [_accessoryContainer setFrameFromContentFrame:accessoryFrame];
        [_accessoryContainer setContentView:accessoryView];
        
        // Tile the container
        containerFrame = [_accessoryContainer frame];
        containerFrame.origin.x = 0.0;
        containerFrame.origin.y = NSMaxY([_bottomSection frame]);
        [_accessoryContainer setFrame:containerFrame];

 
        // Resize the window to accommodate
        rect = [[self view] frame];
        //PENDING: shrink to fit? Check against windows min and max?
        rect.size.width = NSWidth(containerFrame);
        rect.size.height += NSHeight(containerFrame) - height;
        rect = [_openPanel frameRectForContentRect:rect];
        [_openPanel setFrame:rect display:YES];
        
        [[self view] addSubview:_accessoryContainer];
    }
    else
    {
        CGFloat  height;
        
        height = NSHeight([_accessoryContainer frame]);
        [_accessoryContainer setContentView:_initialAccessoryView];
        [_accessoryContainer removeFromSuperview];
        
        rect = [[self view] frame];
        rect.size.height -= height;
        rect = [_openPanel frameRectForContentRect:rect];
        [_openPanel setFrame:rect display:YES];
    }
    
    [_middleSection setAutoresizingMask:mask];
}

- (void)validateVisibleColumns
{
    [[_browserController view] setNeedsDisplay:YES];
    [[_listViewController view] setNeedsDisplay:YES];
    [_iconViewController reload];
    [self validateOKButton];
}

- (void)resetSession
{
    for (CK2FileOperation *operation in [_runningOperations allValues])
    {
        [operation cancel];
    }
    [_runningOperations removeAllObjects];
    
    if (_currentLoadingOperation != nil)
    {
        [_currentLoadingOperation cancel];
        [_currentLoadingOperation release];
        _currentLoadingOperation = nil;
    }

    [_urlCache removeAllObjects];
    [_historyManager removeAllActions];

    [self setURLs:nil];
    
    [_browserController reload];
    [_iconViewController reload];
    [_listViewController reload];

    [self validateViews];
}

- (NSArray *)URLs
{
    if ([_urls count] == 0)
    {
        NSURL   *directoryURL;
        
        directoryURL = [self directoryURL];
        
        if (directoryURL != nil)
        {
            return @[ [self directoryURL] ];
        }
        return nil;
    }
    return _urls;
}

- (NSURL *)URL
{
    NSArray     *urls;
    
    urls = [self URLs];
    if ([urls count] > 0)
    {
        return [urls objectAtIndex:0];
    }
    return nil;
}

- (void)setURL:(NSURL *)URL
{
    [self setURLs:(URL ? @[URL] : nil)];
}

// Called by the open panel. The completion block will not be called until the given URL is loaded.
- (void)changeDirectory:(NSURL *)directoryURL completionHandler:(void (^)(NSError *error))block
{
    // Set it now so that the value can be returned if queried. Don't bother syncing with the UI as it will be set
    // again (possibly with a different value) later.
    [self setDirectoryURL:directoryURL];
    
    
    //PENDING: compare url
    if (_currentLoadingOperation != nil)
    {
        [_currentLoadingOperation cancel];
        [_currentLoadingOperation release];
    }
    
    _currentLoadingOperation = [_fileManager contentsOfDirectoryAtURL:directoryURL includingPropertiesForKeys:[self fileProperties] options:(NSDirectoryEnumerationSkipsSubdirectoryDescendants | CK2DirectoryEnumerationIncludesDirectory) completionHandler:
    ^(NSArray *contents, NSError *blockError)
    {
        if (blockError != nil)
        {
             NSLog(@"Error loading contents of URL %@: %@", directoryURL, blockError);
        }
        else
        {
            NSURL           *resolvedURL;
            NSArray         *children;
            
            // The first url returned is the rootURL properly resolved (in case the URL is relative to the user's home
            // directory, for instance).
            resolvedURL = [[contents objectAtIndex:0] retain];
            
            children = [contents subarrayWithRange:NSMakeRange(1, [contents count] - 1)];
            [self setDirectoryURL:resolvedURL];
            
                [self cacheChildren:children forURL:resolvedURL];
                [self urlDidLoad:resolvedURL];
                
                [_currentLoadingOperation release];
                _currentLoadingOperation = nil;
                
                if (blockError == nil)
                {
                    [self setURLs:@[ resolvedURL ] updateDirectory:YES updateRoot:YES sender:self];
                }
                [self validateViews];
                
                [resolvedURL release];
        }
        
             if (block != NULL)
             {
                 block(blockError);
             }
    }];
    
    // There shouldn't be a race condition with the block above since this should be on the main thread and
    // the above block won't run on the main thread until this code completes and returns to the run loop.
    [_currentLoadingOperation retain];
    
    [_hostField setStringValue:[directoryURL host]];
    [self validateViews];
}


- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)flag
{
    [self setURLs:urls updateDirectory:flag updateRoot:NO sender:nil];
}

- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)updateDir sender:(id)sender
{
    [self setURLs:urls updateDirectory:updateDir updateRoot:NO sender:sender];
}

- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)updateDir updateRoot:(BOOL)updateRoot sender:(id)sender
{
    CK2OpenPanelViewController  *currentController;
    NSTabViewItem               *selectedTab;
    
    [self setURLs:urls];
    [self validateOKButton];
    
    if (updateDir)
    {
        NSURL       *directoryURL;

        directoryURL = [urls objectAtIndex:0];
        if (![self URLCanHazChildren:directoryURL])
        {
            directoryURL = [directoryURL ck2_parentURL];
        }
        
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
 
    [self validateNewFolderButton];

    selectedTab = [_tabView selectedTabViewItem];
    currentController = [self viewControllerForIdentifier:[selectedTab identifier]];
    if ((sender != currentController) || (![currentController hasFixedRoot] && updateDir))
    {
        if (updateRoot)
        {
            [_browserController setRootURL:[self directoryURL]];
        }
        
        if (updateDir)
        {
            [currentController reload];
        }
        [currentController update];
    }
    [_openPanel makeFirstResponder:[selectedTab initialFirstResponder]];
    
    if ([[_openPanel delegate] respondsToSelector:@selector(panelSelectionDidChange:)])
    {
        [[_openPanel delegate] panelSelectionDidChange:_openPanel];
    }
}

- (void)cacheChildren:(NSArray *)children forURL:(NSURL *)url
{
    if (children == nil)
    {
        [_urlCache removeObjectForKey:url];
    }
    else
    {
        NSArray     *sortedChildren;
        
        sortedChildren = [children sortedArrayUsingComparator:[NSURL ck2_displayComparator]];
        [_urlCache setObject:sortedChildren forKey:url];
    }
}

- (NSArray *)childrenForURL:(NSURL *)url
{
    id      children;
        
    children = nil;
    
    if ((url != nil) && [self URLCanHazChildren:url])
    {
        children = [_urlCache objectForKey:url];
        
        if (children == nil)
        {
            CK2FileOperation *operation;
            
            // Placeholder while children are being fetched
            children = @[ [NSURL ck2_loadingURL] ];

            [self cacheChildren:children forURL:url];
            
            if ([_runningOperations objectForKey:url] == nil)
            {
                operation = [_fileManager contentsOfDirectoryAtURL:url
                                        includingPropertiesForKeys:[self fileProperties]
                                                           options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                completionHandler:
                ^(NSArray *contents, NSError *blockError)
                {
                    id             value;

                    value = contents;
                    if (value == nil)
                    {
                        if (blockError != nil)
                        {
                            NSString *errorMessage = blockError.localizedFailureReason;
                            if (!errorMessage) errorMessage = blockError.localizedDescription;
                            
                            value = @[ [NSURL ck2_errorURLWithMessage:errorMessage] ];
                            NSLog(@"Error loading contents of URL %@: %@", url, blockError);
                        }
                        else
                        {
                            // Shouldn't happen
                            NSLog(@"Received nil from -contentsOfDirectoryAtURL: for URL %@ but no error set", url);
                            value = [NSArray array];
                        }
                    }
                    
                        [self cacheChildren:value forURL:url];

                        [_runningOperations removeObjectForKey:url];
                        
                        [self validateProgressIndicator];
                        [self urlDidLoad:url];
                }];

                // There shouldn't be a race condition with the block above since this should be on the main thread and
                // the above block won't run on the main thread until this code completes and returns to the run loop.
                [_runningOperations setObject:operation forKey:url];

                [self validateProgressIndicator];
            }
        }
        else
        {
            if (![[self openPanel] showsHiddenFiles])
            {
                children = [children filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
                                                                  ^BOOL(id evaluatedObject, NSDictionary *bindings)
                                                                  {
                                                                      return ![evaluatedObject ck2_isHidden];
                                                                  }]];
            }
        }
    }
    return children;
}

- (BOOL)isURLValid:(NSURL *)url
{
    if (![url ck2_isPlaceholder])
    {
        id <CK2OpenPanelDelegate>   delegate;
        BOOL                        delegateValid, fileTypeValid;
        NSArray                     *allowedFileTypes;
        
        delegate = [_openPanel delegate];
        
        delegateValid = (![delegate respondsToSelector:@selector(panel:shouldEnableURL:)] || [delegate panel:_openPanel shouldEnableURL:url]);
        
        allowedFileTypes = [_openPanel allowedFileTypes];
        fileTypeValid = ([allowedFileTypes count] == 0) || [allowedFileTypes containsObject:[url pathExtension]];
        
        if ([self URLCanHazChildren:url])
        {
            return [_openPanel canChooseDirectories] && delegateValid && fileTypeValid;
        }
        else
        {
            return [_openPanel canChooseFiles] && delegateValid && fileTypeValid;
        }
    }
    return NO;
}

- (BOOL)URLCanHazChildren:(NSURL *)url
{
    return [url ck2_isDirectory] && (![url ck2_isPackage] || [_openPanel treatsFilePackagesAsDirectories]);
}

- (void)urlDidLoad:(NSURL *)url
{
    [[self currentViewController] urlDidLoad:url];
    [self validateNewFolderButton];
}

- (CK2OpenPanelViewController *)currentViewController
{
    return [self viewControllerForIdentifier:[[_tabView selectedTabViewItem] identifier]];
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
    
    enable = (_currentLoadingOperation == nil);
    
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
    NSURL                       *url;
    NSArray                     *urls;
    BOOL                        urlIsLoading;
    CK2OpenPanelViewController  *currentController;
    
    urlIsLoading = NO;
    currentController = [self currentViewController];

    urls = [currentController selectedURLs];
    
    if ([urls count] > 0)
    {
        for (url in urls)
        {
            if ([_runningOperations objectForKey:url] != nil)
            {
                urlIsLoading = YES;
                break;
            }
        }
    }
    else
    {
        urlIsLoading = ([_runningOperations objectForKey:[self directoryURL]] != nil);
    }
    
    if ((_currentLoadingOperation == nil) && !urlIsLoading)
    {
        [_progressIndicator stopAnimation:self];
        [_progressIndicator setHidden:YES];
        [_refreshButton setHidden:NO];
    }
    else
    {
        [_refreshButton setHidden:YES];
        [_progressIndicator startAnimation:self];
        [_progressIndicator setHidden:NO];
    }
}

- (IBAction)refresh:(id)sender
{
    NSURL                       *url;
    NSArray                     *urls;
    BOOL                        urlIsLoading;
    CK2OpenPanelViewController  *viewController;
    NSResponder                 *firstResponder;
    
    urlIsLoading = NO;
    urls = [self URLs];
    
    if ([urls count] == 0)
    {
        urls = @[ [self directoryURL] ];
    }
    
    for (url in urls)
    {
        if ([_runningOperations objectForKey:url] != nil)
        {
            urlIsLoading = YES;
            break;
        }
    }
    
    if (!urlIsLoading)
    {
        for (url in urls)
        {
            [self cacheChildren:nil forURL:url];
        }
    }

    viewController = [self currentViewController];
    firstResponder = [[self openPanel] firstResponder];
    if ([firstResponder isKindOfClass:[NSView class]] && [(NSView *)firstResponder isDescendantOf:[viewController view]])
    {
        firstResponder = [viewController view];
    }

    [viewController reload];
    [viewController update];
    
    [[self openPanel] makeFirstResponder:firstResponder];
    [self validateNewFolderButton];
    [self validateProgressIndicator];
}

- (void)validateHomeButton
{
}

- (void)validateOKButton
{
    BOOL    isValid;
    
    isValid = NO;
    if (_currentLoadingOperation == nil)
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

- (void)validateNewFolderButton
{
    NSArray     *children;
    BOOL        childrenLoaded;
    
    children = [self childrenForURL:[self directoryURL]];
    
    childrenLoaded = (children != nil) && (([children count] != 1) || ![[children objectAtIndex:0] ck2_isPlaceholder]);
    [_newFolderButton setEnabled:childrenLoaded];
}

- (IBAction)newFolder:(id)sender
{
    CK2NewFolderWindowController    *controller;
    NSURL                           *parentURL;
    
    controller = [[CK2NewFolderWindowController alloc] initWithController:self];
    parentURL = [self directoryURL];
    
    if ([controller runModalForURL:parentURL])
    {
        NSURL           *url;
        NSArray             *children;
        NSMutableArray      *newChildren;
        NSUInteger          i;
        
        url = [controller folderURL];
        
        children = [_urlCache objectForKey:parentURL];
        newChildren = [NSMutableArray arrayWithArray:children];
        
        i = [newChildren indexOfObject:url inSortedRange:NSMakeRange(0, [newChildren count]) options:NSBinarySearchingInsertionIndex usingComparator:[NSURL ck2_displayComparator]];

        [newChildren insertObject:url atIndex:i];
        
        [self cacheChildren:newChildren forURL:parentURL];
        [self setURLs:@[ url ] updateDirectory:YES updateRoot:NO sender:nil];
    }
    else if ([controller error] != nil)
    {
        NSLog(@"Could not create directory under URL %@: %@", parentURL, [controller error]);
        NSBeginCriticalAlertSheet(NSLocalizedStringFromTableInBundle(@"Could not create folder", nil, [NSBundle bundleForClass:[self class]], @"Create folder error"),
                                  NSLocalizedStringFromTableInBundle(@"OK", nil, [NSBundle bundleForClass:[self class]], @"OK Button"), nil, nil, [self openPanel], nil, NULL, NULL, NULL, @"%@", [[controller error] localizedDescription]);
    }
    
    [controller release];
}

- (void)validateHistoryButtons
{
    [_historyButtons setEnabled:((_currentLoadingOperation == nil) && ([_historyManager canUndo])) forSegment:0];
    [_historyButtons setEnabled:((_currentLoadingOperation == nil) && ([_historyManager canRedo])) forSegment:1];
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
    NSTabViewItem       *tabItem;
    NSUInteger          i;
    
    [self addToHistory];

    [self setURLs:@[ [dict objectForKey:HISTORY_DIRECTORY_URL_KEY] ] updateDirectory:YES];
    
    i = [[dict objectForKey:HISTORY_DIRECTORY_VIEW_INDEX_KEY] unsignedIntegerValue];
    tabItem = [_tabView tabViewItemAtIndex:i];
    
    [[self viewControllerForIdentifier:[tabItem identifier]] restoreViewHistoryState:dict];
    [_tabView selectTabViewItemAtIndex:i];
}

- (void)addToHistory
{
    NSMutableDictionary         *dict;
    CK2OpenPanelViewController  *currentController;
    NSTabViewItem               *tabItem;
    NSURL                       *directoryURL;
    
    directoryURL = [self directoryURL];
    
    // If nil, indicates an error so should not push it on the undo stack
    if (directoryURL != nil)
    {
        tabItem = [_tabView selectedTabViewItem];
        
        dict = [NSMutableDictionary dictionary];
        [dict setObject:[self directoryURL] forKey:HISTORY_DIRECTORY_URL_KEY];
        [dict setObject:[NSNumber numberWithUnsignedInteger:[_tabView indexOfTabViewItem:tabItem]] forKey:HISTORY_DIRECTORY_VIEW_INDEX_KEY];
        
        currentController = [self viewControllerForIdentifier:[tabItem identifier]];
        [currentController saveViewHistoryState:dict];
        
        [_historyManager registerUndoWithTarget:self selector:@selector(changeView:) object:dict];
        
        [self validateHistoryButtons];
    }
}

- (IBAction)home:(id)sender
{
    NSURL   *homeURL;
    
    homeURL = [self homeURL];
    
    if (homeURL == nil)
    {
        if (_currentLoadingOperation != nil)
        {
            [_currentLoadingOperation cancel];
            [_currentLoadingOperation release];
        }

        // The homeURL isn't resolved so we resolve it here and also load/cache its children.        
        homeURL = [CK2FileManager URLWithPath:@"" isDirectory:YES hostURL:[self directoryURL]];
        
        _currentLoadingOperation = [_fileManager contentsOfDirectoryAtURL:homeURL includingPropertiesForKeys:[self fileProperties] options:CK2DirectoryEnumerationIncludesDirectory completionHandler:
        ^(NSArray *contents, NSError *blockError)
        {
            NSArray     *children;
            NSURL       *resolvedURL;
            
            resolvedURL = homeURL;
            if (blockError != nil)
            {
                NSString *errorMessage = blockError.localizedFailureReason;
                if (!errorMessage) errorMessage = blockError.localizedDescription;
                
                children = @[ [NSURL ck2_errorURLWithMessage:errorMessage] ];
                NSLog(@"Error loading contents of URL %@: %@", homeURL, blockError);
            }
            else
            {
                resolvedURL = [contents objectAtIndex:0];
                children = [contents subarrayWithRange:NSMakeRange(1, [contents count] - 1)];
            }
            
                [self setHomeURL:resolvedURL];
                [self cacheChildren:children forURL:resolvedURL];

                [_currentLoadingOperation release];
                _currentLoadingOperation = nil;

                [self validateProgressIndicator];
                [self urlDidLoad:resolvedURL];
                               
                [self setURLs:@[ resolvedURL ] updateDirectory:YES updateRoot:YES sender:self ];
        }];
        
        // There shouldn't be a race condition with the block above since this should be on the main thread and
        // the above block won't run on the main thread until this code completes and returns to the run loop.
        [_currentLoadingOperation retain];
        
        [self validateProgressIndicator];
    }
    else
    {
        [self setURLs:@[ homeURL ] updateDirectory:YES updateRoot:YES sender:self ];
    }
}

- (void)goToSelectedItem:(id)sender
{
    [[self currentViewController] goToSelectedItem:(id)sender];
}

- (void)showPathFieldWithString:(NSString *)string
{
    if (_pathFieldController == nil)
    {
        _pathFieldController = [[CK2PathFieldWindowController alloc] init];
    }
    [_pathFieldController setStringValue:string];
    
    [_pathFieldController beginSheetModalForWindow:[self openPanel] completionHandler:
     ^(NSInteger result)
     {
         if (result == NSOKButton)
         {
             NSString   *path;
             
             path = [_pathFieldController stringValue];
             
             if ([path hasPrefix:@"~"])
             {
                 path = [path substringFromIndex:1];
                 
                 if ([path hasPrefix:@"/"])
                 {
                     path = [path substringFromIndex:1];
                 }
             }
             
             [self addToHistory];
             
             [self changeDirectory:[CK2FileManager URLWithPath:path isDirectory:YES hostURL:[self directoryURL]] completionHandler:
              ^(NSError *error)
              {
                  if (error != nil)
                  {
                      NSLog(@"Could not switch to URL %@: %@", [self directoryURL], error);
                      NSBeginCriticalAlertSheet(NSLocalizedStringFromTableInBundle(@"Could not switch to folder", nil, [NSBundle bundleForClass:[self class]], @"Switch folder error"),
                                                NSLocalizedStringFromTableInBundle(@"OK", nil, [NSBundle bundleForClass:[self class]], @"OK Button"), nil, nil, [self openPanel], nil, NULL, NULL, NULL, @"%@", [error localizedDescription]);

                      
                      // NSOpenPanel will try and select as much of the URL as is valid. We don't do that here since it may
                      // take a while to resolve each ancestor so we just revert back to the previous directory.
                      [self back:self];
                  }
              }];
         }
     }];
}

- (IBAction)pathControlItemSelected:(id)sender
{
    NSURL       *url;
    
    url = [_pathControl URL];
    
    if (![url isEqual:[self directoryURL]])
    {
        [self addToHistory];
        [self setURLs:@[ url ] updateDirectory:YES updateRoot:YES sender:_pathControl];
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
    NSString  *identifier;
    
    [_openPanel makeFirstResponder:[tabViewItem initialFirstResponder]];
    
    identifier = [tabViewItem identifier];
    
    if (![identifier isEqual:BLANK_VIEW_IDENTIFIER])
    {
        [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:CK2OpenPanelLastViewPrefKey];
    }
}

#pragma mark CK2FileManagerDelegate

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    id <CK2OpenPanelDelegate>        delegate;
    
    delegate = [[self openPanel] delegate];
    
    if ([delegate respondsToSelector:@selector(panel:didReceiveChallenge:completionHandler:)])
    {
        [delegate panel:self.openPanel didReceiveChallenge:challenge completionHandler:completionHandler];
    }
    else
    {
        completionHandler(CK2AuthChallengePerformDefaultHandling, nil);
    }
}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
    id <CK2OpenPanelDelegate>        delegate;
    
    delegate = [[self openPanel] delegate];
    
    if ([delegate respondsToSelector:@selector(panel:appendString:toTranscript:)])
    {
        [delegate panel:[self openPanel] appendString:info toTranscript:transcript];
    }
}

@end

/*  
 * TNModuleLoader.j
 *    
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import <StropheCappuccino/StropheCappuccino.j>

@import "TNCategoriesAndGlobalSubclasses.j";

/*! @global
    @group TNArchipelModuleType
    type for tab module
*/
TNArchipelModuleTypeTab     = @"tab";

/*! @global
    @group TNArchipelModuleType
    type for toolbar module
*/
TNArchipelModuleTypeToolbar = @"toolbar";


/*! this notification is sent when all modules are loaded
*/
TNArchipelModulesLoadingCompleteNotification = @"TNArchipelModulesLoadingCompleteNotification"

/*! @ingroup archipelcore
    
    this is the Archipel Module loader.
    It supports 3 delegates :
    
     - moduleLoader:hasLoadBundle: is sent when a module is loaded
     - moduleLoader:willLoadBundle: is sent when a module will be loaded
     - moduleLoaderLoadingComplete: is sent when all modules has been loaded
*/
@implementation TNModuleLoader: CPObject
{
    TNToolbar               mainToolbar                     @accessors;
    CPTabView               mainTabView                     @accessors;
    id                      delegate                        @accessors;
    
    TNStropheRoster         roster                          @accessors;
    id                      entity                          @accessors;
    CPString                moduleType                      @accessors;
    CPString                modulesPath                     @accessors;
    CPView                  mainRightView                   @accessors;
    CPMenu                  modulesMenu                     @accessors;

    id                      _modulesPList;
    CPArray                 _bundles;
    CPDictionary            _loadedTabModulesScrollViews;
    CPDictionary            _loadedToolbarModulesScrollViews;
    CPString                _previousStatus;
    CPView                  _currentToolbarView;
    CPToolbarItem           _currentToolbarItem;
    int                     _numberOfModulesToLoad;
    int                     _numberOfModulesLoaded;
}

/*! initialize the module loader
    @return an initialized instance of TNModuleLoader
*/
- (void)init
{
    if (self = [super init])
    {
        _loadedTabModulesScrollViews     = [CPDictionary dictionary];
        _loadedToolbarModulesScrollViews = [CPDictionary dictionary];
        _numberOfModulesToLoad = 0;
        _numberOfModulesLoaded = 0;
        _bundles = [CPArray array];
    }

    return self;
}

/*! set the XMPP information that will be gave to Tabs Modules.
    @param anEntity id can contains a TNStropheContact or a TNStropheGroup
    @param aType a type of entity. Can be virtualmachine, hypervisor, user or group
    @param aRoster TNStropheRoster the roster where the TNStropheContact besides
*/
- (void)setEntity:(id)anEntity ofType:(CPString)aType andRoster:(TNStropheRoster)aRoster
{
    [self rememberLastSelectedTabIndex];
    
    var center = [CPNotificationCenter defaultCenter];
    
    [self _removeAllTabsFromModulesTabView];
    
    [self setEntity:anEntity];
    [self setRoster:aRoster];
    [self setModuleType:aType];

    [center removeObserver:self];
    [center addObserver:self selector:@selector(_didPresenceUpdate:) name:TNStropheContactPresenceUpdatedNotification object:entity];
    [center addObserver:self selector:@selector(_didReceiveVcard:) name:TNStropheContactVCardReceivedNotification object:entity];
    
    if ([[self entity] class] == TNStropheContact)
    {
        _previousStatus = [[self entity] status];
        if (([[self entity] class] == TNStropheContact) && ([[self entity] status] != TNStropheContactStatusOffline))
            [self _populateModulesTabView];
    }
    else
        [self _populateModulesTabView];
}

/*! store in TNUserDefaults last selected tab index for entity
*/
- (void)rememberLastSelectedTabIndex
{
    if ([self entity] && ([[self mainTabView] numberOfTabViewItems] > 0))
    {
        var currentItem = [[self mainTabView] selectedTabViewItem];
        
        [self rememberSelectedIndexOfItem:currentItem];
    }
}

/*! set wich item tab to remember
    @param anItem: the CPTabView item to remember
*/
- (void)rememberSelectedIndexOfItem:(id)anItem
{
    if (anItem && [self entity] && ([mainTabView numberOfTabViewItems] > 0))
    {
        var identifier;
        var memid;
        var defaults                = [TNUserDefaults standardUserDefaults];
        var currentSelectedIndex    = [mainTabView indexOfTabViewItem:anItem];
        
        if ([[self entity] class] == TNStropheContact)
            identifier = [[self entity] JID];
        else
            identifier = [[self entity] name];

        memid = @"selectedTabIndexFor" + identifier;
        
        [defaults setInteger:currentSelectedIndex forKey:memid];
    }
}

/*! Reselect the last remembered tab index for entity
*/
- (void)recoverFromLastSelectedIndex
{
    var identifier;
    if ([[self entity] class] == TNStropheContact)
        identifier = [[self entity] JID];
    else
        identifier = [[self entity] name];
    
    var defaults            = [TNUserDefaults standardUserDefaults];
    var memid               = @"selectedTabIndexFor" + identifier;
    var oldSelectedIndex    = [defaults integerForKey:memid];
    var numberOfTabItems    = [[self mainTabView] numberOfTabViewItems];
    
    if ([self entity] && (numberOfTabItems > 0) && ((numberOfTabItems - 1) >= oldSelectedIndex) && (oldSelectedIndex != -1))
    {
        CPLog.debug("recovering last selected tab index " + oldSelectedIndex);
        [[self mainTabView] selectTabViewItemAtIndex:oldSelectedIndex];
    }
}

/*! Set the roster and the connection for the Toolbar Modules.
    @param aRoster TNStropheRoster a connected roster
    @param aConnection the connection used by the roster
*/
- (void)setRosterForToolbarItems:(TNStropheRoster)aRoster andConnection:(TNStropheConnection)aConnection
{
    var allValues = [_loadedToolbarModulesScrollViews allValues];

    for(var i = 0; i < [allValues count]; i++)
    {
        var toolbarModule = [[allValues objectAtIndex:i] documentView];
        [toolbarModule initializeWithEntity:nil connection:aConnection andRoster:aRoster];
    }

}

/*! analyse the content of vCard will return the TNArchipelEntityType
    @param aVCard TNXMLNode containing the vCard
    @return value of TNArchipelEntityType
*/
- (CPString)analyseVCard:(TNXMLNode)aVCard
{
    if (aVCard)
    {
        var itemType = [[aVCard firstChildWithName:@"TYPE"] text];

        if ((itemType == TNArchipelEntityTypeVirtualMachine) || (itemType == TNArchipelEntityTypeHypervisor)
            || (itemType == TNArchipelEntityTypeGroup))
            return itemType;
        else
            return TNArchipelEntityTypeUser;
    }

    return TNArchipelEntityTypeUser;
}

/*! will start to load all the bundles describe in modules.plist
*/
- (void)load
{
    [self unloadAllModules];
    
    var request     = [CPURLRequest requestWithURL:[CPURL URLWithString:@"Modules/modules.plist"]];
    var connection  = [CPURLConnection connectionWithRequest:request delegate:self];
        
    //[connection cancel];
    [connection start];
}

- (void)unloadAllModules
{

}

/// PRIVATES

/*! will load all CPBundle
*/
- (void)_loadAllBundles
{
    CPLog.debug("going to parse the PList");
    
    for(var i = 0; i < [[_modulesPList objectForKey:@"Modules"] count]; i++)
    {
        CPLog.debug("parsing " + [CPBundle bundleWithPath:path]);
        
        var module  = [[_modulesPList objectForKey:@"Modules"] objectAtIndex:i];
        var path    = [self modulesPath] + [module objectForKey:@"folder"];
        var bundle  = [CPBundle bundleWithPath:path];
        
        _numberOfModulesToLoad++;    
            
        if ([delegate respondsToSelector:@selector(moduleLoader:willLoadBundle:)])
            [delegate moduleLoader:self willLoadBundle:bundle];
                       
        [bundle loadWithDelegate:self];
    }
    
    if ((_numberOfModulesToLoad == 0) && ([delegate respondsToSelector:@selector(moduleLoaderLoadingComplete:)]))
        [delegate moduleLoaderLoadingComplete:self];
}

/*! will display the modules that have to be displayed according to the entity type.
    triggered by -setEntity:ofType:andRoster:
*/
- (void)_populateModulesTabView
{
    var allValues = [_loadedTabModulesScrollViews allValues];

    var sortedValue = [allValues sortedArrayUsingFunction:function(a, b, context){
        var indexA = [[a documentView] moduleTabIndex];
        var indexB = [[b documentView] moduleTabIndex];
        if (indexA < indexB)
                return CPOrderedAscending;
            else if (indexA > indexB)
                return CPOrderedDescending;
            else
                return CPOrderedSame;
    }]
    
    //@each(var module in [_modulesPList objectForKey:@"Modules"])
    for(var i = 0; i < [sortedValue count]; i++)
    {
        var module      = [[sortedValue objectAtIndex:i] documentView];
        var moduleTypes = [module moduleTypes];
        var moduleIndex = [module moduleTabIndex];
        var moduleLabel = [module moduleLabel];
        var moduleName  = [module moduleName];

        if ([moduleTypes containsObject:[self moduleType]])
        {
            [self _addItemToModulesTabViewWithLabel:moduleLabel moduleView:[sortedValue objectAtIndex:i] atIndex:moduleIndex];
        }
    }    
    
    [self recoverFromLastSelectedIndex];
}

/*! will remove all loaded modules and send message willUnload to all TNModules
*/
- (void)_removeAllTabsFromModulesTabView
{
    if ([mainTabView numberOfTabViewItems] <= 0)
        return;
        
    var arrayCpy        = [[mainTabView tabViewItems] copy];
    // var selectedItem    = [mainTabView selectedTabViewItem];
    // var theModule       = [[selectedItem view] documentView];

    //@each(var aTabViewItem in [self tabViewItems])
    for(var i = 0; i < [arrayCpy count]; i++)
    {
        var aTabViewItem    = [arrayCpy objectAtIndex:i];
        var theModule       = [[aTabViewItem view] documentView];

        [theModule willUnload];
        [theModule setEntity:nil];
        [theModule setRoster:nil];

        [[aTabViewItem view] removeFromSuperview];
        [mainTabView removeTabViewItem:aTabViewItem];
    }
}

/*! insert a TNModules embeded in a scroll view to the mainToolbarView CPView
    @param aLabel CPString containing the displayed label
    @param aModuleScrollView CPScrollView containing the TNModule
    @param anIndex CPNumber representing the insertion index
*/
- (void)_addItemToModulesTabViewWithLabel:(CPString)aLabel moduleView:(CPScrollView)aModuleScrollView atIndex:(CPNumber)anIndex
{
    var newViewItem     = [[CPTabViewItem alloc] initWithIdentifier:aLabel];
    var theEntity       = [self entity];
    var theConnection   = [[self entity] connection];
    var theRoster       = [self roster];
    var theModule       = [aModuleScrollView documentView];
    
    [theModule initializeWithEntity:theEntity connection:theConnection andRoster:theRoster];
    [theModule willLoad];

    [newViewItem setLabel:aLabel];
    [newViewItem setView:aModuleScrollView];

    [mainTabView addTabViewItem:newViewItem];
}

/*! triggered on TNStropheContactPresenceUpdatedNotification receiption. This will sent _removeAllTabsFromModulesTabView
    to self if presence if Offline. If presence was Offline and bacame online, it will ask for the vCard to
    know what TNModules to load.
*/
- (void)_didPresenceUpdate:(CPNotification)aNotification
{
    if ([[aNotification object] status] == TNStropheContactStatusOffline)
    {
        [self _removeAllTabsFromModulesTabView];
        _previousStatus = TNStropheContactStatusOffline;
    }
    else if (([[aNotification object] status] == TNStropheContactStatusOnline) && (_previousStatus) && (_previousStatus == TNStropheContactStatusOffline))
    {
        _previousStatus = nil;
        
        [self _removeAllTabsFromModulesTabView];
        [self _populateModulesTabView];
    }

}

/*! triggered on vCard reception
    @param aNotification CPNotification that trigger the selector
*/
- (void)_didReceiveVcard:(CPNotification)aNotification
{
    var vCard   = [[aNotification object] vCard];
    
    if ([vCard text] != [[entity vCard] text])
    {
        [self setModuleType:[self analyseVCard:vCard]];

        [self _removeAllTabsFromModulesTabView];
        [self _populateModulesTabView];
    }
}


/// DELEGATES

/*! CPTabView delegate. Will sent willHide to current tab module and willShow to the one that will be be display
    @param aTabView the CPTabView that sent the message (mainTabView)
    @param anItem the new selected item
*/
- (void)tabView:(CPTabView)aTabView willSelectTabViewItem:(CPTabViewItem)anItem
{
    if ([aTabView numberOfTabViewItems] <= 0)
        return
    
    
    var currentTabItem = [aTabView selectedTabViewItem];
    
    if (currentTabItem)
    {
        var oldModule = [[currentTabItem view] documentView];
        [oldModule willHide];
    }
    
    var newModule = [[anItem view] documentView];
    [newModule willShow];
}

/*! delegate of CPURLConnection triggered when modules.plist is loaded.
    @param connection CPURLConnection that sent the message
    @param data CPString containing the result of the url
*/
- (void)connection:(CPURLConnection)connection didReceiveData:(CPString)data
{
    var cpdata = [CPData dataWithRawString:data];

    CPLog.info("Module.plist recovered");

    _modulesPList = [cpdata plistObject];
    
    [self _removeAllTabsFromModulesTabView];
    
    [self _loadAllBundles];
}

/*! delegate of CPBundle. Will initialize all the modules in plist
    @param aBundle CPBundle that sent the message
*/
- (void)bundleDidFinishLoading:(CPBundle)aBundle
{
    _numberOfModulesLoaded++;

    [_bundles addObject:aBundle];

    var moduleName          = [aBundle objectForInfoDictionaryKey:@"CPBundleName"];
    var moduleCibName       = [aBundle objectForInfoDictionaryKey:@"CibName"];
    var moduleLabel         = [aBundle objectForInfoDictionaryKey:@"PluginDisplayName"];
    var moduleInsertionType = [aBundle objectForInfoDictionaryKey:@"InsertionType"];
    var moduleIdentifier    = [aBundle objectForInfoDictionaryKey:@"CPBundleIdentifier"];

    var theViewController   = [[CPViewController alloc] initWithCibName:moduleCibName bundle:aBundle];
    var scrollView          = [[CPScrollView alloc] initWithFrame:[[self mainRightView] bounds]];

    [scrollView setAutoresizingMask:CPViewHeightSizable | CPViewWidthSizable];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setBackgroundColor:[CPColor whiteColor]];

    var frame = [[scrollView contentView] bounds];
    
    [[theViewController view] setAutoresizingMask: CPViewWidthSizable];
    [[theViewController view] setModuleName:moduleName];
    [[theViewController view] setModuleLabel:moduleLabel];
    [[theViewController view] setModuleBundle:aBundle];

    if (moduleInsertionType == TNArchipelModuleTypeTab)
    {
        var moduleTabIndex      = [aBundle objectForInfoDictionaryKey:@"TabIndex"];
        var supportedTypes      = [aBundle objectForInfoDictionaryKey:@"SupportedEntityTypes"];
        var module              = [theViewController view];
        
        var moduleItem          = [modulesMenu addItemWithTitle:moduleLabel action:nil keyEquivalent:@""];
        [moduleItem setEnabled:NO];
        [moduleItem setTarget:module];
        
        var moduleRootMenu  = [[CPMenu alloc] init];
        [modulesMenu setSubmenu:moduleRootMenu forItem:moduleItem];
        
        [module setMenuItem:moduleItem];
        [module setMenu:moduleRootMenu];
        
        [module setModuleTypes:supportedTypes];
        [module setModuleTabIndex:moduleTabIndex];

        [module menuReady];

        [_loadedTabModulesScrollViews setObject:scrollView forKey:moduleName];
        frame.size.height = [[theViewController view] bounds].size.height;
    }
    else if (moduleInsertionType == TNArchipelModuleTypeToolbar)
    {
        var moduleToolbarIndex = [aBundle objectForInfoDictionaryKey:@"ToolbarIndex"];

        [[self mainToolbar] addItemWithIdentifier:moduleName label:moduleLabel icon:[aBundle pathForResource:@"icon.png"] target:self action:@selector(didToolbarModuleClicked:)];
        [[self mainToolbar] setPosition:moduleToolbarIndex forToolbarItemIdentifier:moduleName];

        [[theViewController view] willLoad];

        [[self mainToolbar] _reloadToolbarItems];

        [_loadedToolbarModulesScrollViews setObject:scrollView forKey:moduleName];
    }

    [[theViewController view] setFrame:frame];
    [scrollView setDocumentView:[theViewController view]];
    
    
    if ([delegate respondsToSelector:@selector(moduleLoader:hasLoadBundle:)])
        [delegate moduleLoader:self hasLoadBundle:aBundle];
        
    if (_numberOfModulesLoaded >= _numberOfModulesToLoad)
    {
        var center = [CPNotificationCenter defaultCenter];
        [center postNotificationName:TNArchipelModulesLoadingCompleteNotification object:self];
        
        if ([delegate respondsToSelector:@selector(moduleLoaderLoadingComplete:)])
            [delegate moduleLoaderLoadingComplete:self];
    }
}

/*! Action that respond on Toolbar TNModules to display the view of the module.
    @param sender the CPToolbarItem that sent the message
*/
- (IBAction)didToolbarModuleClicked:(id)sender
{
    var oldView;

    if (_currentToolbarView)
    {
        var moduleBundle    = [[_currentToolbarView documentView] moduleBundle];
        var iconPath        = [moduleBundle pathForResource:[moduleBundle objectForInfoDictionaryKey:@"ToolbarIcon"]];

        //[_currentToolbarItem setLabel:[moduleBundle objectForInfoDictionaryKey:@"PluginDisplayName"]];
        [_currentToolbarItem setImage:[[CPImage alloc] initWithContentsOfFile:iconPath size:CPSizeMake(32,32)]];

        [[_currentToolbarView documentView] willHide];
        [_currentToolbarView removeFromSuperview];

        oldView = _currentToolbarView;

        _currentToolbarView = nil;
        _currentToolbarItem = nil;
    }

    var view            = [_loadedToolbarModulesScrollViews objectForKey:[sender itemIdentifier]];

    if (oldView != view)
    {
        var bounds          = [[self mainRightView] bounds];
        var moduleBundle    = [[view documentView] moduleBundle];
        var iconPath        = [moduleBundle pathForResource:[moduleBundle objectForInfoDictionaryKey:@"AlternativeToolbarIcon"]];

        //[sender setLabel:[moduleBundle objectForInfoDictionaryKey:@"AlternativePluginDisplayName"]];
        [sender setImage:[[CPImage alloc] initWithContentsOfFile:iconPath size:CPSizeMake(32,32)]];

        [view setFrame:bounds];

        [[view documentView] willShow];

        [[self mainRightView] addSubview:view];

        _currentToolbarView = view;
        _currentToolbarItem = sender;
    }
}
@end

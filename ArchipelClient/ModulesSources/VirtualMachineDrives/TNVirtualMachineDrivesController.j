/*
 * TNViewHypervisorControl.j
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

@import <AppKit/CPButton.j>
@import <AppKit/CPButtonBar.j>
@import <AppKit/CPSearchField.j>
@import <AppKit/CPTableView.j>
@import <AppKit/CPTextField.j>
@import <AppKit/CPView.j>

@import <TNKit/TNAlert.j>
@import <TNKit/TNTableViewDataSource.j>

@import "TNNewDriveController.j"
@import "TNEditDriveController.j"
@import "TNDriveDataView.j"
@import "TNDriveObject.j"


var TNArchipelTypeVirtualMachineDisk        = @"archipel:vm:disk",
    TNArchipelTypeVirtualMachineDiskCreate  = @"create",
    TNArchipelTypeVirtualMachineDiskDelete  = @"delete",
    TNArchipelTypeVirtualMachineDiskGet     = @"get",
    TNArchipelPushNotificationDisk          = @"archipel:push:disk",
    TNArchipelPushNotificationAppliance     = @"archipel:push:vmcasting",
    TNArchipelPushNotificationDiskCreated   = @"created";

TNArchipelDrivesFormats = [@"qcow2", @"qcow", @"cow", @"raw", @"vmdk"];

/*! @defgroup  virtualmachinedrives Module VirtualMachine Drives
    @desc Allows to create and manage virtual drives
*/

/*! @ingroup virtualmachinedrives
    main class of the module
*/
@implementation TNVirtualMachineDrivesController : TNModule
{
    @outlet CPButtonBar             buttonBarControl;
    @outlet CPSearchField           fieldFilter;
    @outlet CPView                  viewTableContainer;
    @outlet TNEditDriveController   editDriveController;
    @outlet TNNewDriveController    newDriveController;
    @outlet TNDriveDataView         dataViewDrivePrototype;
    @outlet CPTableView             tableMedias;
    BOOL                            _isEntityOnline               @accessors(getter=isEntityOnline);

    CPButton                        _editButton;
    CPButton                        _minusButton;
    CPButton                        _plusButton;

    id                              _registredDiskListeningId;
    TNTableViewDataSource           _mediasDatasource;
}


#pragma mark -
#pragma mark Initialization

/*! called at cib awaking
*/
- (void)awakeFromCib
{
    [viewTableContainer setBorderedWithHexColor:@"#C0C7D2"];

    var bundle = [CPBundle mainBundle];

    // Media table view
    _mediasDatasource    = [[TNTableViewDataSource alloc] init];
    [tableMedias setTarget:self];
    [tableMedias setDoubleAction:@selector(openEditWindow:)];
    [tableMedias setDelegate:self];
    [tableMedias setSelectionHighlightStyle:CPTableViewSelectionHighlightStyleNone];
    [tableMedias setBackgroundColor:[CPColor colorWithHexString:@"F7F7F7"]];

    [[tableMedias tableColumnWithIdentifier:@"self"] setDataView:[dataViewDrivePrototype duplicate]];
    [_mediasDatasource setSearchableKeyPaths:[@"name", @"path", @"format"]];
    [_mediasDatasource setTable:tableMedias];
    [tableMedias setDataSource:_mediasDatasource];

    [fieldFilter setTarget:_mediasDatasource];
    [fieldFilter setAction:@selector(filterObjects:)];

    _plusButton  = [CPButtonBar plusButton];
    [_plusButton setTarget:self];
    [_plusButton setAction:@selector(openNewDiskWindow:)];

    _minusButton  = [CPButtonBar minusButton];
    [_minusButton setTarget:self];
    [_minusButton setAction:@selector(removeDisk:)];
    [_minusButton setEnabled:NO];

    _editButton  = [CPButtonBar plusButton];
    [_editButton setImage:[[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/edit.png"] size:CPSizeMake(16, 16)]];
    [_editButton setTarget:self];
    [_editButton setAction:@selector(openEditWindow:)];
    [_editButton setEnabled:NO];

    [buttonBarControl setButtons:[_plusButton, _minusButton, _editButton]];

    [newDriveController setDelegate:self];
    [editDriveController setDelegate:self];
}


#pragma mark -
#pragma mark TNModule overrides

/*! called when module is loaded
*/
- (BOOL)willLoad
{
    if (![super willLoad])
        return NO;

    _registredDiskListeningId = nil;

    var params = [CPDictionary dictionary];

    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationDisk]
    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationAppliance]

    [[CPNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_didUpdatePresence:)
                                                 name:TNStropheContactPresenceUpdatedNotification
                                               object:_entity];

    [tableMedias setDelegate:nil];
    [tableMedias setDelegate:self];

    [self getDisksInfo];

    return YES;
}

/*! called when module becomes visible
*/
- (BOOL)willShow
{
    if (![super willShow])
        return NO;

    [self checkIfRunning];
    [self getDisksInfo];

    return YES;
}

/*! called when module is hidden
*/
- (void)willHide
{
    [editDriveController closeWindow:nil];
    [newDriveController closeWindow:nil];

    [super willHide];
}

/*! called when MainMenu is ready
*/
- (void)menuReady
{
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Create a drive", @"Create a drive") action:@selector(openNewDiskWindow:) keyEquivalent:@""] setTarget:self];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Edit selected drive", @"Edit selected drive") action:@selector(openEditWindow:) keyEquivalent:@""] setTarget:self];
    [_menu addItem:[CPMenuItem separatorItem]];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Delete selected drive", @"Delete selected drive") action:@selector(removeDisk:) keyEquivalent:@""] setTarget:self];
}

/*! called when user permissions changed
*/
- (void)permissionsChanged
{
    [super permissionsChanged];
    [self tableViewSelectionDidChange:nil];
}

/*! called when the UI needs to be updated according to the permissions
*/
- (void)setUIAccordingToPermissions
{
    if (![self currentEntityHasPermission:@"drives_create"])
        [newDriveController closeWindow:nil];

    if (![self currentEntityHasPermissions:[@"drives_convert", @"drives_rename"]])
        [editDriveController closeWindow:nil];
}

/*! this message is used to flush the UI
*/
- (void)flushUI
{
    [_mediasDatasource removeAllObjects];
    [tableMedias reloadData];
}

#pragma mark -
#pragma mark Notification handlers

/*! called if entity changes it presence and call checkIfRunning
    @param aNotification the notification
*/
- (void)_didUpdatePresence:(CPNotification)aNotification
{
    if ([aNotification object] == _entity)
    {
        [self checkIfRunning];
    }
}

/*! called when an Archipel push is received
    @param somePushInfo CPDictionary containing the push information
*/
- (BOOL)_didReceivePush:(CPDictionary)somePushInfo
{
    var sender  = [somePushInfo objectForKey:@"owner"],
        type    = [somePushInfo objectForKey:@"type"],
        change  = [somePushInfo objectForKey:@"change"],
        date    = [somePushInfo objectForKey:@"date"];

    if (type == TNArchipelPushNotificationDisk)
    {
        if (change == @"created")
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"Disk has been created", @"Disk has been created")];
        else if (change == @"deleted")
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"Disk has been removed", @"Disk has been removed")];
    }

    [self getDisksInfo];

    return YES;
}


#pragma mark -
#pragma mark  Utilities

/*! checks if virtual machine is running. if yes, display ythe masking view
*/
- (void)checkIfRunning
{
    var XMPPShow = [_entity XMPPShow];

    _isEntityOnline = ((XMPPShow == TNStropheContactStatusOnline) || (XMPPShow == TNStropheContactStatusAway));

    if (XMPPShow == TNStropheContactStatusBusy)
        [self showMaskView:NO];
    else
        [self showMaskView:YES];
}


#pragma mark -
#pragma mark Actions

/*! opens the new disk window
    @param aSender the sender of the action
*/
- (IBAction)openNewDiskWindow:(id)aSender
{
    [self requestVisible];
    if (![self isVisible])
        return;

    [newDriveController openWindow:_plusButton];
}

/*! opens the rename window
    @param aSender the sender of the action
*/
- (IBAction)openEditWindow:(id)aSender
{
    if (![self currentEntityHasPermissions:[@"drives_convert", @"drives_rename"]])
        return;

    [self requestVisible];
    if (![self isVisible])
        return;

    if (_isEntityOnline)
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"You can't edit disks of a running virtual machine", @"You can't edit disks of a running virtual machine")
                                                            icon:TNGrowlIconError];
    }
    else
    {
        if ([tableMedias numberOfSelectedRows] <= 0)
             return;

        if ([tableMedias numberOfSelectedRows] > 1)
        {
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"You can't edit multiple disk", @"You can't edit multiple disk")
                                                                icon:TNGrowlIconError];
            return;
        }

        var selectedIndex   = [[tableMedias selectedRowIndexes] firstIndex],
            diskObject      = [_mediasDatasource objectAtIndex:selectedIndex];

        [editDriveController setCurrentEditedDisk:diskObject];

        if ([aSender isKindOfClass:CPMenuItem])
            aSender = _editButton;

        [editDriveController openWindow:aSender];
    }
}

/*! remove a disk
    @param aSender the sender of the action
*/
- (IBAction)removeDisk:(id)aSender
{
    [self requestVisible];
    if (![self isVisible])
        return;

    [self removeDisk];
}


#pragma mark -
#pragma mark XMPP Controls

/*! ask virtual machine for its disks
*/
- (void)getDisksInfo
{
    var stanza = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineDisk}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineDiskGet}];

    [self setModuleStatus:TNArchipelModuleStatusWaiting];
    [_entity sendStanza:stanza andRegisterSelector:@selector(_didReceiveDisksInfo:) ofObject:self];
}

/*! compute virtual machine disk
    @param aStanza TNStropheStanza that contains the answer
*/
- (BOOL)_didReceiveDisksInfo:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [_mediasDatasource removeAllObjects];
        var disks = [aStanza childrenWithName:@"disk"];

        for (var i = 0; i < [disks count]; i++)
        {
            var disk        = [disks objectAtIndex:i],
                vSize       = [CPString formatByteSize:[disk valueForAttribute:@"virtualSize"]],
                dSize       = [CPString formatByteSize:[disk valueForAttribute:@"diskSize"]],
                path        = [disk valueForAttribute:@"path"],
                name        = [disk valueForAttribute:@"name"],
                format      = [disk valueForAttribute:@"format"],
                backingFile = [disk valueForAttribute:@"backingFile"],
                drive       = [TNDrive mediaWithPath:path name:name format:format virtualSize:vSize diskSize:dSize backingFile:backingFile];

            [_mediasDatasource addObject:drive];
        }
        [tableMedias reloadData];
        [self setModuleStatus:TNArchipelModuleStatusReady];
    }
    else
    {
        [self setModuleStatus:TNArchipelModuleStatusError];
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! asks virtual machine to remove a disk. but before ask a confirmation
*/
- (void)removeDisk
{
    if (([tableMedias numberOfRows]) && ([tableMedias numberOfSelectedRows] <= 0))
    {
         [TNAlert showAlertWithMessage:CPBundleLocalizedString(@"Error", @"Error")
                           informative:CPBundleLocalizedString(@"You must select a media", @"You must select a media")];
         return;
    }

    var alert = [TNAlert alertWithMessage:CPBundleLocalizedString(@"Delete to drive", @"Delete to drive")
                                informative:CPBundleLocalizedString(@"Are you sure you want to destroy this drive ? this is not reversible.", @"Are you sure you want to destroy this drive ? this is not reversible.")
                                 target:self
                                 actions:[[CPBundleLocalizedString(@"Delete", @"Delete"), @selector(performRemoveDisk:)], [CPBundleLocalizedString(@"Cancel", @"Cancel"), nil]]];
    [alert runModal];
}

/*! asks virtual machine to remove a disk
*/
- (void)performRemoveDisk:(id)someUserInfo
{
    var selectedIndexes = [tableMedias selectedRowIndexes],
        objects         = [_mediasDatasource objectsAtIndexes:selectedIndexes];

    for (var i = 0; i < [objects count]; i++)
    {
        var dName   = [objects objectAtIndex:i],
            stanza  = [TNStropheStanza iqWithType:@"set"];

        [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineDisk}];
        [stanza addChildWithName:@"archipel" andAttributes:{
            "xmlns": TNArchipelTypeVirtualMachineDisk,
            "action": TNArchipelTypeVirtualMachineDiskDelete,
            "name": [dName path],
            "undefine": "yes"}];

        [_entity sendStanza:stanza andRegisterSelector:@selector(_didRemoveDisk:) ofObject:self];
    }
}

/*! compute virtual machine disk removing results
    @param aStanza TNStropheStanza that contains the answer
*/
- (BOOL)_didRemoveDisk:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"error")
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}


#pragma mark -
#pragma mark Delegates

- (void)tableViewSelectionDidChange:(CPTableView)aTableView
{
    [self setControl:_plusButton enabledAccordingToPermission:@"drives_create"];
    [self setControl:_minusButton enabledAccordingToPermission:@"drives_delete" specialCondition:([tableMedias numberOfSelectedRows] > 0)];
    [self setControl:_editButton enabledAccordingToPermissions:[@"drives_convert", @"drives_rename"] specialCondition:([tableMedias numberOfSelectedRows] > 0)];
}


@end


// add this code to make the CPLocalizedString looking at
// the current bundle.
function CPBundleLocalizedString(key, comment)
{
    return CPLocalizedStringFromTableInBundle(key, nil, [CPBundle bundleForClass:TNVirtualMachineDrivesController], comment);
}


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
@import <AppKit/CPImage.j>
@import <AppKit/CPImageView.j>
@import <AppKit/CPSearchField.j>
@import <AppKit/CPSegmentedControl.j>
@import <AppKit/CPSlider.j>
@import <AppKit/CPTableView.j>
@import <AppKit/CPTextField.j>
@import <AppKit/CPView.j>

@import <TNKit/TNAlert.j>
@import <TNKit/TNTableViewDataSource.j>
@import <TNKit/TNTextFieldStepper.j>

@import "TNExtendedContactObject.j"



var TNArchipelPushNotificationDefinition            = @"archipel:push:virtualmachine:definition",
    TNArchipelPushNotificationControl               = @"archipel:push:virtualmachine:control",
    TNArchipelPushNotificationOOM                   = @"archipel:push:virtualmachine:oom",
    TNArchipelControlNotification                   = @"TNArchipelControlNotification",
    TNArchipelControlPlay                           = @"TNArchipelControlPlay",
    TNArchipelControlSuspend                        = @"TNArchipelControlSuspend",
    TNArchipelControlResume                         = @"TNArchipelControlResume",
    TNArchipelControlStop                           = @"TNArchipelControlStop",
    TNArchipelControlDestroy                        = @"TNArchipelControlDestroy",
    TNArchipelControlReboot                         = @"TNArchipelControlReboot",
    TNArchipelTypeVirtualMachineControl             = @"archipel:vm:control",
    TNArchipelTypeVirtualMachineOOM                 = @"archipel:vm:oom",
    TNArchipelTypeVirtualMachineVMParking           = @"archipel:vm:vmparking",
    TNArchipelTypeVirtualMachineControlInfo         = @"info",
    TNArchipelTypeVirtualMachineControlCreate       = @"create",
    TNArchipelTypeVirtualMachineControlShutDown     = @"shutdown",
    TNArchipelTypeVirtualMachineControlDestroy      = @"destroy",
    TNArchipelTypeVirtualMachineControlFree         = @"free",
    TNArchipelTypeVirtualMachineControlReboot       = @"reboot",
    TNArchipelTypeVirtualMachineControlSuspend      = @"suspend",
    TNArchipelTypeVirtualMachineControlResume       = @"resume",
    TNArchipelTypeVirtualMachineControlMigrate      = @"migrate",
    TNArchipelTypeVirtualMachineControlAutostart    = @"autostart",
    TNArchipelTypeVirtualMachineControlMemory       = @"memory",
    TNArchipelTypeVirtualMachineControlVCPUs        = @"setvcpus",
    TNArchipelTypeVirtualMachineControlScreenshot   = @"screenshot",
    TNArchipelTypeVirtualMachineOOMSetAdjust        = @"setadjust",
    TNArchipelTypeVirtualMachineOOMGetAdjust        = @"getadjust",
    TNArchipelTypeVirtualMachineVMParkingPark       = @"park",
    VIR_DOMAIN_NOSTATE                              = 0,
    VIR_DOMAIN_RUNNING                              = 1,
    VIR_DOMAIN_BLOCKED                              = 2,
    VIR_DOMAIN_PAUSED                               = 3,
    VIR_DOMAIN_SHUTDOWN                             = 4,
    VIR_DOMAIN_SHUTOFF                              = 5,
    VIR_DOMAIN_CRASHED                              = 6,
    TNArchipelTransportBarPlay                      = 0,
    TNArchipelTransportBarPause                     = 1,
    TNArchipelTransportBarStop                      = 2,
    TNArchipelTransportBarDestroy                   = 3,
    TNArchipelTransportBarReboot                    = 4;


/*! @defgroup  virtualmachinecontrols Module VirtualMachine Controls
    @desc Allow to controls virtual machine
*/

/*! @ingroup virtualmachinecontrols
    main class of the module
*/
@implementation TNVirtualMachineControlsController : TNModule
{
    @outlet CPBox                   boxAdvancedCommands;
    @outlet CPButton                buttonKill;
    @outlet CPButton                buttonPark;
    @outlet CPButton                buttonScreenshot;
    @outlet CPButtonBar             buttonBarMigration;
    @outlet CPCheckBox              checkBoxAdvancedCommands;
    @outlet CPImageView             imageState;
    @outlet CPSearchField           filterHypervisors;
    @outlet CPSegmentedControl      buttonBarTransport;
    @outlet CPSlider                sliderMemory;
    @outlet CPTableView             tableHypervisors;
    @outlet CPTextField             fieldInfoConsumedCPU;
    @outlet CPTextField             fieldInfoMem;
    @outlet CPTextField             fieldInfoState;
    @outlet CPTextField             fieldOOMAdjust;
    @outlet CPTextField             fieldOOMScore;
    @outlet CPTextField             fieldPreferencesScreenshotRefresh;
    @outlet CPView                  viewTableHypervisorsContainer;
    @outlet TNSwitch                switchAutoStart;
    @outlet TNSwitch                switchPreventOOMKiller;
    @outlet TNTextFieldStepper      stepperCPU;

    CPButton                        _migrateButton;
    CPImage                         _imageDestroy;
    CPImage                         _imagePause;
    CPImage                         _imagePlay;
    CPImage                         _imageReboot;
    CPImage                         _imageResume;
    CPImage                         _imageScreenShutDown;
    CPImage                         _imageStop;
    CPImageView                     _imageViewFullScreenshot;
    CPNumber                        _VMLibvirtStatus;
    CPString                        _currentHypervisorJID;
    CPTimer                         _screenshotTimer;
    TNAttachedWindow                _attachedWindowScreenshot;
    TNStropheContact                _virtualMachineToFree;
    TNTableViewDataSource           _datasourceHypervisors;
}


#pragma mark -
#pragma mark Initialization

/*! called at cib awaking
*/
- (void)awakeFromCib
{
    var bundle      = [CPBundle bundleForClass:[self class]],
        defaults    = [CPUserDefaults standardUserDefaults];

    // register defaults defaults
    [defaults registerDefaults:[CPDictionary dictionaryWithObjectsAndKeys:
           [bundle objectForInfoDictionaryKey:@"TNArchipelControlsMaxVCPUs"], @"TNArchipelControlsMaxVCPUs",
           [bundle objectForInfoDictionaryKey:@"TNArchipelControlsScreenshotRefresh"], @"TNArchipelControlsScreenshotRefresh"
    ]];

    [boxAdvancedCommands setCornerRadius:3.0];

    [sliderMemory setContinuous:YES];
    [stepperCPU setTarget:self];
    [stepperCPU setAction:@selector(setVCPUs:)];
    [stepperCPU setMinValue:1];
    [stepperCPU setMaxValue:[defaults integerForKey:@"TNArchipelControlsMaxVCPUs"]];
    [stepperCPU setValueWraps:NO];
    [stepperCPU setAutorepeat:NO];

    _imagePlay      = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/play.png"] size:CGSizeMake(16, 16)];
    _imageStop      = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/stop.png"] size:CGSizeMake(16, 16)];
    _imageDestroy   = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/destroy.png"] size:CGSizeMake(16, 16)];
    _imagePause     = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/pause.png"] size:CGSizeMake(16, 16)];
    _imageReboot    = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/reboot.png"] size:CGSizeMake(16, 16)];

    [buttonBarTransport setSegmentCount:5];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Play", @"Play") forSegment:TNArchipelTransportBarPlay];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Pause", @"Pause") forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Stop", @"Stop") forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Destroy", @"Destroy") forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Reboot", @"Reboot") forSegment:TNArchipelTransportBarReboot];

    [buttonBarTransport setWidth:100 forSegment:TNArchipelTransportBarPlay];
    [buttonBarTransport setWidth:100 forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setWidth:100 forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setWidth:100 forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setWidth:100 forSegment:TNArchipelTransportBarReboot];

    [buttonBarTransport setImage:_imagePlay forSegment:TNArchipelTransportBarPlay];
    [buttonBarTransport setImage:_imagePause forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setImage:_imageStop forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setImage:_imageDestroy forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setImage:_imageReboot forSegment:TNArchipelTransportBarReboot];

    [buttonBarTransport setTarget:self];
    [buttonBarTransport setAction:@selector(segmentedControlClicked:)];

    // table migration
    [viewTableHypervisorsContainer setBorderedWithHexColor:@"#C0C7D2"];
    _datasourceHypervisors   = [[TNTableViewDataSource alloc] init];
    [tableHypervisors setTarget:self];
    [tableHypervisors setDoubleAction:@selector(migrate:)];
    [_datasourceHypervisors setTable:tableHypervisors];
    [tableHypervisors setDataSource:_datasourceHypervisors];

    // button bar migration
    _migrateButton  = [CPButtonBar plusButton];
    [_migrateButton setImage:[[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"IconsButtons/migrate.png"] size:CPSizeMake(16, 16)]];
    [_migrateButton setTarget:self];
    [_migrateButton setAction:@selector(migrate:)];
    [_migrateButton setEnabled:NO];

    [buttonBarMigration setButtons:[_migrateButton]];

    [switchAutoStart setTarget:self];
    [switchAutoStart setAction:@selector(setAutostart:)];

    [switchPreventOOMKiller setTarget:self];
    [switchPreventOOMKiller setAction:@selector(setPreventOOMKiller:)];

    // screenshot image
    _imageScreenShutDown = [[CPImage alloc] initWithContentsOfFile:[bundle pathForResource:@"shutdown.png"] size:CGSizeMake(216, 162)];
    [buttonScreenshot setBackgroundColor:[CPColor blackColor]];
    [buttonScreenshot setBordered:NO];

    _attachedWindowScreenshot = [[TNAttachedWindow alloc] initWithContentRect:CPRectMake(0.0, 0.0, 800.0, 620.0) styleMask:TNAttachedBlackWindowMask | CPClosableWindowMask];
    _imageViewFullScreenshot = [[CPImageView alloc] initWithFrame:CPRectMake(0.0, 20.0, 800.0, 600.0)],
    [[_attachedWindowScreenshot contentView] addSubview:_imageViewFullScreenshot];
}


#pragma mark -
#pragma mark TNModule overrides

/*! called when module is loaded
*/
- (BOOL)willLoad
{
    if (![super willLoad])
        return NO;

    [[CPNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_didReceiveControlNotification:)
                                                 name:TNArchipelControlNotification
                                               object:nil];

    [[CPNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_didUpdatePresence:)
                                                 name:TNStropheContactPresenceUpdatedNotification
                                               object:_entity];

    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationControl];
    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationDefinition];
    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationOOM];

    [self disableAllButtons];

    [imageState setImage:[_entity statusIcon]];

    return YES;
}

/*! called when module is unloaded
*/
- (void)willUnload
{
    [fieldInfoMem setStringValue:@"..."];
    [fieldInfoConsumedCPU setStringValue:@"..."];
    [fieldInfoState setStringValue:@"..."];
    [imageState setImage:nil];

    [self disableAllButtons];
    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Pause", @"Pause") forSegment:TNArchipelTransportBarPause];

    [super willUnload];
}

/*! called when module becomes visible
*/
- (BOOL)willShow
{
    if (![super willShow])
        return NO;

    _screenshotTimer = nil;
    [self checkIfRunning];

    [buttonScreenshot setImage:_imageScreenShutDown];
    [tableHypervisors setDelegate:nil];
    [tableHypervisors setDelegate:self];

    [viewTableHypervisorsContainer setHidden:YES];
    [filterHypervisors setHidden:YES];
    [switchAutoStart setEnabled:NO];
    [switchAutoStart setOn:NO animated:YES sendAction:NO];
    [sliderMemory setEnabled:NO];
    [stepperCPU setEnabled:NO];

    [buttonKill setEnabled:NO];
    [buttonPark setEnabled:NO];
    [checkBoxAdvancedCommands setState:CPOffState];

    [tableHypervisors deselectAll];
    [self populateHypervisorsTable];

    return YES;
}

/*! called when module becomes unvisible
*/
- (void)willHide
{
    if (_screenshotTimer)
        [_screenshotTimer invalidate];
    _screenshotTimer = nil;
    [buttonScreenshot setImage:_imageScreenShutDown];
    [super willHide];
}

/*! called when MainMenu is ready
*/
- (void)menuReady
{
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Start", @"Start") action:@selector(play:) keyEquivalent:@""] setTarget:self];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Shut down", @"Shut down") action:@selector(stop:) keyEquivalent:@""] setTarget:self];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Pause / Resume", @"Pause / Resume") action:@selector(pause:) keyEquivalent:@""] setTarget:self];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Reboot", @"Reboot") action:@selector(reboot:) keyEquivalent:@""] setTarget:self];
    [[_menu addItemWithTitle:CPBundleLocalizedString(@"Destroy", @"Destroy") action:@selector(destroy:) keyEquivalent:@""] setTarget:self];
}

/*! called when user saves preferences
*/
- (void)savePreferences
{
    var defaults = [CPUserDefaults standardUserDefaults];

    [defaults setInteger:[fieldPreferencesScreenshotRefresh intValue] forKey:@"TNArchipelControlsScreenshotRefresh"];
}

/*! called when user gets preferences
*/
- (void)loadPreferences
{
    var defaults = [CPUserDefaults standardUserDefaults];

    [fieldPreferencesScreenshotRefresh setIntValue:[defaults integerForKey:@"TNArchipelControlsScreenshotRefresh"]];
}

/*! called when user permissions changed
*/
- (void)permissionsChanged
{
    [super permissionsChanged];
    [self checkIfRunning];
}

/*! called when the UI needs to be updated according to the permissions
*/
- (void)setUIAccordingToPermissions
{
    var isOnline = ([_entity XMPPShow] == TNStropheContactStatusOnline);

    [self setControl:switchPreventOOMKiller enabledAccordingToPermissions:[@"oom_getadjust", @"oom_setadjust"]];
    [self setControl:switchAutoStart enabledAccordingToPermission:@"autostart"];
    [self setControl:sliderMemory enabledAccordingToPermission:@"memory" specialCondition:isOnline];
    [self setControl:stepperCPU enabledAccordingToPermission:@"setvcpus" specialCondition:isOnline];
    [self setControl:buttonKill enabledAccordingToPermission:@"free"];
    [self setControl:buttonPark enabledAccordingToPermission:@"vmparking_park"];

    [viewTableHypervisorsContainer setHidden:!([self currentEntityHasPermission:@"migrate"] && isOnline)];
    [filterHypervisors setHidden:!([self currentEntityHasPermission:@"migrate"] && isOnline)];

    [self setControl:buttonBarTransport segment:TNArchipelTransportBarPlay enabledAccordingToPermission:@"create"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarStop enabledAccordingToPermission:@"shutdown"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarDestroy enabledAccordingToPermission:@"destroy"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarPause enabledAccordingToPermissions:[@"suspend", @"resume"]];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarReboot enabledAccordingToPermission:@"reboot"];

    if (_VMLibvirtStatus)
        [self layoutButtons:_VMLibvirtStatus];
}

/*! this message is used to flush the UI
*/
- (void)flushUI
{
    [_datasourceHypervisors removeAllObjects];
    [tableHypervisors reloadData];
}


#pragma mark -
#pragma mark Notification handlers

/*! called if entity changes it presence and call checkIfRunning
    @param aNotification the notification
*/
- (void)_didUpdatePresence:(CPNotification)aNotification
{
    [imageState setImage:[_entity statusIcon]];

    [self checkIfRunning];
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

    [self checkIfRunning];

    return YES;
}

/*! called when recieve a control notification
*/
- (void)_didReceiveControlNotification:(CPNotification)aNotification
{
    var command = [aNotification userInfo];

    switch (command)
    {
        case TNArchipelControlPlay:
            [self play:nil];
            break;
        case (TNArchipelControlSuspend || TNArchipelControlResume):
            [self pause:nil];
            break;
        case TNArchipelControlReboot:
            [self reboot:nil];
            break;
        case TNArchipelControlStop:
            [self stop:nil];
            break;
        case TNArchipelControlDestroy:
            [self destroy:nil];
            break;
    }
}

/*! proxy for screenshot timer
*/
- (void)getThumbnailScreenshot:(CPTimer)aTimer
{
    [self getThumbnailScreenshot];
}

#pragma mark -
#pragma mark Utilities

/*! check if virtual machine is running and adapt the GUI
*/
- (void)checkIfRunning
{
    if (![self isVisible])
        return;

    if ([self currentEntityHasPermission:@"info"])
        [self getVirtualMachineInfo];

    if ([self currentEntityHasPermission:@"oom_getadjust"])
        [self getOOMKiller];
}

/*! populate the migration table with all hypervisors in roster
*/
- (void)populateHypervisorsTable
{
    [_datasourceHypervisors removeAllObjects];
    var rosterItems = [[[TNStropheIMClient defaultClient] roster] contacts];

    for (var i = 0; i < [rosterItems count]; i++)
    {
        var item = [rosterItems objectAtIndex:i];

        if ([[[TNStropheIMClient defaultClient] roster] analyseVCard:[item vCard]] == TNArchipelEntityTypeHypervisor)
        {
            var o = [[TNExtendedContact alloc] initWithNickName:[item nickname] fullJID:[[item JID] full]];

            [_datasourceHypervisors addObject:o];
        }
    }
    [tableHypervisors reloadData];

}

/*! layout segmented controls button according to virtual machine state
    @pathForResource libvirtState the state of the virtual machine
*/
- (void)layoutButtons:(id)libvirtState
{
    var humanState;

    switch ([libvirtState intValue])
    {
        case VIR_DOMAIN_NOSTATE:
            humanState = CPBundleLocalizedString(@"No status", @"No status");
            break;
        case VIR_DOMAIN_RUNNING:
        case VIR_DOMAIN_BLOCKED:
            [self enableButtonsForRunning];
            humanState = CPBundleLocalizedString(@"Running", @"Running");
            break;
        case VIR_DOMAIN_PAUSED:
            [self enableButtonsForPaused]
            humanState = CPBundleLocalizedString(@"Paused", @"Paused");
            break;
        case VIR_DOMAIN_SHUTDOWN:
            [self enableButtonsForShutDown]
            humanState = CPBundleLocalizedString(@"Off", @"Off");
            break;
        case VIR_DOMAIN_SHUTOFF:
            [self enableButtonsForShutDown]
            humanState = CPBundleLocalizedString(@"Off", @"Off");
            break;
        case VIR_DOMAIN_CRASHED:
            humanState = CPBundleLocalizedString(@"Crashed", @"Crashed");
            break;
  }
  [fieldInfoState setStringValue:humanState];
  [imageState setImage:[_entity statusIcon]];
}

/*! enable buttons necessary when virtual machine is running
*/
- (void)enableButtonsForRunning
{
    [buttonBarTransport setSelectedSegment:TNArchipelTransportBarPlay];

    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarPlay];

    [self setControl:buttonBarTransport segment:TNArchipelTransportBarStop enabledAccordingToPermission:@"shutdown"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarDestroy enabledAccordingToPermission:@"destroy"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarPause enabledAccordingToPermissions:[@"suspend", @"resume"]];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarReboot enabledAccordingToPermission:@"reboot"];

    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Pause", @"Pause") forSegment:TNArchipelTransportBarPause];

    [self setControl:switchPreventOOMKiller enabledAccordingToPermissions:[@"oom_getadjust", @"oom_setadjust"]]
}

/*! enable buttons necessary when virtual machine is paused
*/
- (void)enableButtonsForPaused
{
    [buttonBarTransport setSelectedSegment:TNArchipelTransportBarPause];

    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarPlay]
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarStop enabledAccordingToPermission:@"shutdown"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarDestroy enabledAccordingToPermission:@"destroy"];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarPause enabledAccordingToPermissions:[@"suspend", @"resume"]];
    [self setControl:buttonBarTransport segment:TNArchipelTransportBarReboot enabledAccordingToPermission:@"reboot"];

    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Resume", @"Resume") forSegment:TNArchipelTransportBarPause];

    [self setControl:switchPreventOOMKiller enabledAccordingToPermissions:[@"oom_getadjust", @"oom_setadjust"]]
}

/*! enable buttons necessary when virtual machine is shut down
*/
- (void)enableButtonsForShutDown
{
    [buttonBarTransport setSelectedSegment:TNArchipelTransportBarStop];

    [self setControl:buttonBarTransport segment:TNArchipelTransportBarPlay enabledAccordingToPermission:@"create"];

    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarReboot];

    [buttonBarTransport setLabel:CPBundleLocalizedString(@"Pause", @"Pause") forSegment:TNArchipelTransportBarPause];

    [switchPreventOOMKiller setEnabled:NO]
}

/*! disable all buttons
*/
- (void)disableAllButtons
{
    [buttonBarTransport setSelected:NO forSegment:TNArchipelTransportBarPlay];
    [buttonBarTransport setSelected:NO forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setSelected:NO forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setSelected:NO forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setSelected:NO forSegment:TNArchipelTransportBarReboot];

    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarPlay];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarStop];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarDestroy];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarPause];
    [buttonBarTransport setEnabled:NO forSegment:TNArchipelTransportBarReboot];

    [switchPreventOOMKiller setEnabled:NO];
}


#pragma mark -
#pragma mark Action

/*! triggered when segmented control is clicked
    @param aSender the sender of the action
*/
- (IBAction)segmentedControlClicked:(id)aSender
{
    var segment = [aSender selectedSegment];

    switch (segment)
    {
        case TNArchipelTransportBarPlay:
            [self play];
            break;
        case TNArchipelTransportBarPause:
            [self pause];
            break;
        case TNArchipelTransportBarStop:
            [self stop];
            break;
        case TNArchipelTransportBarDestroy:
            [self destroy];
            break;
        case TNArchipelTransportBarReboot:
            [self reboot];
            break;
    }
}

/*! send play command
    @param aSender the sender of the action
*/
- (IBAction)play:(id)aSender
{
    [self play];
}

/*! send pause command
    @param aSender the sender of the action
*/
- (IBAction)pause:(id)aSender
{
    [self pause];
}

/*! send stop command
    @param aSender the sender of the action
*/
- (IBAction)stop:(id)aSender
{
    [self stop];
}

/*! send destroy command
    @param aSender the sender of the action
*/
- (IBAction)destroy:(id)aSender
{
    [self destroy];
}

/*! send reboot command
    @param aSender the sender of the action
*/
- (IBAction)reboot:(id)aSender
{
    [self reboot];
}

/*! send set autostart command
    @param sender the sender of the action
*/
- (IBAction)setAutostart:(id)aSender
{
    [self setAutostart];
}

/*! send disable or enable the OOM killer for this virtual machine
    @param sender the sender of the action
*/
- (IBAction)setPreventOOMKiller:(id)aSender
{
    [self setPreventOOMKiller];
}

/*! send set memory command
    @param aSender the sender of the action
*/
- (IBAction)setMemory:(id)aSender
{
    if ([[CPApp currentEvent] type] == CPLeftMouseUp)
    {
        [self setMemory];
    }
    else
    {
        [fieldInfoMem setTextColor:[CPColor grayColor]];
        [fieldInfoMem setStringValue:Math.round([sliderMemory intValue] / 1024) + @" MB"];
    }
}

/*! send set vCPUs command
    @param aSender the sender of the action
*/
- (IBAction)setVCPUs:(id)aSender
{
    [self setVCPUs];
}

/*! send migrate command
    @param aSender the sender of the action
*/
- (IBAction)migrate:(id)aSender
{
    [self migrate];
}

/*! send free command
    @param aSender the sender of the action
*/
- (IBAction)free:(id)aSender
{
    [self free];
}

/*! send park command
    @param aSender the sender of the action
*/
- (IBAction)park:(id)aSender
{
    [self park];
}

/*! open the full screenshot window
    @param aSender the sender of the action
*/
- (IBAction)openFullScreenshotWindow:(id)aSender
{
    [self getFullScreenshot];
}

/*! Set if the advanced controls should be enabled or disabled
    @param aSender the sender of the action
*/
- (IBAction)manageAdvancedControls:(id)aSender
{
    [buttonPark setEnabled:([aSender state] == CPOnState)];
    [buttonKill setEnabled:([aSender state] == CPOnState)];
}

#pragma mark -
#pragma mark XMPP Controls

/*! ask virtual machine information
*/
- (void)getVirtualMachineInfo
{
    var stanza  = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlInfo}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didReceiveVirtualMachineInfo:)];
}

/*! compute virtual machine answer about its information
*/
- (BOOL)_didReceiveVirtualMachineInfo:(TNStropheStanza)aStanza
{
    if ([aStanza type] != @"result")
        return NO;

    var humanState,
        defaults            = [CPUserDefaults standardUserDefaults],
        infoNode            = [aStanza firstChildWithName:@"info"],
        libvirtState        = [infoNode valueForAttribute:@"state"],
        cpuTime             = Math.round(parseInt([infoNode valueForAttribute:@"cpuTime"]) / 60000000000),
        mem                 = parseFloat([infoNode valueForAttribute:@"memory"]),
        maxMem              = parseFloat([infoNode valueForAttribute:@"maxMem"]),
        autostart           = parseInt([infoNode valueForAttribute:@"autostart"]),
        hypervisor          = [infoNode valueForAttribute:@"hypervisor"],
        nvCPUs              = [infoNode valueForAttribute:@"nrVirtCpu"];

    _currentHypervisorJID = hypervisor;

    [fieldInfoMem setTextColor:[CPColor blackColor]];
    [fieldInfoMem setStringValue:parseInt(mem / 1024) + @" MB"];
    [fieldInfoConsumedCPU setStringValue:cpuTime + @" min"];

    [stepperCPU setDoubleValue:[nvCPUs intValue]];

    if ([_entity XMPPShow] == TNStropheContactStatusOnline || [_entity XMPPShow] == TNStropheContactStatusAway)
    {
        [sliderMemory setMinValue:0];
        [sliderMemory setMaxValue:parseInt(maxMem)];
        [sliderMemory setIntValue:parseInt(mem)];

        [self setControl:sliderMemory enabledAccordingToPermission:@"memory"];
        [self setControl:stepperCPU enabledAccordingToPermission:@"setvcpus"];

        if (!_screenshotTimer && [self isVisible])
        {
            [self getThumbnailScreenshot];
            _screenshotTimer = [CPTimer scheduledTimerWithTimeInterval:[defaults integerForKey:@"TNArchipelControlsScreenshotRefresh"]
                                             target:self
                                           selector:@selector(getThumbnailScreenshot:)
                                           userInfo:nil
                                            repeats:NO];
        }

        if ([self currentEntityHasPermission:@"migrate"])
        {
            [viewTableHypervisorsContainer setHidden:NO];
            [filterHypervisors setHidden:NO];
        }
    }
    else
    {
        if (_screenshotTimer)
            [_screenshotTimer invalidate];

        [sliderMemory setEnabled:NO];
        [sliderMemory setMinValue:0];
        [sliderMemory setMaxValue:100];
        [sliderMemory setIntValue:0];
        [stepperCPU setEnabled:NO];
    }

    [self setControl:switchAutoStart enabledAccordingToPermission:@"autostart"];

    if (autostart == 1)
        [switchAutoStart setOn:YES animated:YES sendAction:NO];
    else
        [switchAutoStart setOn:NO animated:YES sendAction:NO];

    _VMLibvirtStatus = libvirtState;

    [self disableAllButtons];
    [self layoutButtons:libvirtState];

    for (var i = 0; i < [_datasourceHypervisors count]; i++ )
    {
        var item = [_datasourceHypervisors objectAtIndex:i];

        if ([item fullJID] == _currentHypervisorJID)
            [item setSelected:YES];
        else
            [item setSelected:NO];
    }
    [tableHypervisors reloadData];

    var index = [[tableHypervisors selectedRowIndexes] firstIndex];
    if (index != -1)
    {
        var selectedHypervisor = [_datasourceHypervisors objectAtIndex:index];

        if ([selectedHypervisor fullJID] == _currentHypervisorJID)
            [_migrateButton setEnabled:NO];
    }

    return NO;
}

/*! ask virtual machine screenshot
*/
- (void)getThumbnailScreenshot
{
    var stanza  = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlScreenshot,
        "size": "thumbnail"}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didReceiveThumbnailScreenshot:)];
}

/*! compute virtual machine send it's screenshot
*/
- (BOOL)_didReceiveThumbnailScreenshot:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var dataNode = [aStanza firstChildWithName:@"screenshot"];

        if (!dataNode)
        {
            [buttonScreenshot setImage:_imageScreenShutDown];
            return NO;
        }

        var base64Data = [dataNode text],
            screenshot = [[CPImage alloc] initWithData:[CPData dataWithBase64:base64Data]];

        [screenshot setDelegate:self];

        if (_screenshotTimer)
        {
            [_screenshotTimer invalidate];
            _screenshotTimer = nil;
        }

        // next part will be done in imageDidLoad: to ensure image is ready
    }
    return NO;
}

/*! ask virtual machine screenshot
*/
- (void)getFullScreenshot
{
    var stanza  = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlScreenshot,
        "size": "full"}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didReceiveFullScreenshot:)];
}

/*! compute virtual machine send it's screenshot
*/
- (BOOL)_didReceiveFullScreenshot:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var dataNode = [aStanza firstChildWithName:@"screenshot"];

        if (!dataNode)
            return NO;

        var base64Data = [dataNode text],
            screenshotWidth = [dataNode valueForAttribute:@"width"],
            screenshotHeight = [dataNode valueForAttribute:@"height"],
            screenshot = [[CPImage alloc] initWithData:[CPData dataWithBase64:base64Data]];

        [_imageViewFullScreenshot setFrameSize:CPSizeMake(screenshotWidth, screenshotHeight)];
        [_attachedWindowScreenshot setFrameSize:CPSizeMake(screenshotWidth, screenshotHeight)];
        [_imageViewFullScreenshot setImage:screenshot];
        [_attachedWindowScreenshot positionRelativeToView:buttonScreenshot gravity:TNAttachedWindowGravityAuto];
    }
    return NO;
}


/*! send play command
*/
- (void)play
{
    var stanza = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{"action": TNArchipelTypeVirtualMachineControlCreate}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didPlay:)];
}

/*! compute the play result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didPlay:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine is running.", @"Virtual machine is running.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send pause or resume command
*/
- (void)pause
{
    var stanza  = [TNStropheStanza iqWithType:@"set"],
        selector;

    if ([_entity XMPPShow] == TNStropheContactStatusAway)
    {
        selector = @selector(_didResume:)

        [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
        [stanza addChildWithName:@"archipel" andAttributes:{
            "xmlns": TNArchipelTypeVirtualMachineControl,
            "action": TNArchipelTypeVirtualMachineControlResume}];
    }
    else if ([_entity XMPPShow] == TNStropheContactStatusOnline)
    {
        selector = @selector(_didPause:)

        [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
        [stanza addChildWithName:@"archipel" andAttributes:{
            "xmlns": TNArchipelTypeVirtualMachineControl,
            "action": TNArchipelTypeVirtualMachineControlSuspend}];
    }

    [self sendStanza:stanza andRegisterSelector:selector];
}

/*! compute the pause result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didPause:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [self enableButtonsForPaused];
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine is paused.", @"Virtual machine is paused.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    [self layoutButtons:_VMLibvirtStatus];

    return NO;
}

/*! compute the resume result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didResume:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine was resumed.", @"Virtual machine was resumed.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    [self layoutButtons:_VMLibvirtStatus];

    return NO;
}

/*! send stop command
*/
- (void)stop
{
    var stanza  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlShutDown}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didStop:)];
}

/*! compute the stop result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didStop:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine is shutting down.", @"Virtual machine is shutting down.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send destroy command. but ask for user confirmation
*/
- (void)destroy
{
    if (![[CPUserDefaults standardUserDefaults] boolForKey:@"TNArchipelTypeVirtualMachineControlDoNotShowDestroyAlert"])
    {
        var alert = [TNAlert alertWithMessage:[CPString stringWithFormat:CPBundleLocalizedString(@"Unplug %@?", @"Unplug %@?"), [_entity nickname]]
                                    informative:CPBundleLocalizedString(@"Destroying a virtual machine is dangerous. It is equivalent to removing the power plug of a real computer.", @"Destroying a virtual machine is dangerous. It is equivalent to removing the power plug of a real computer.")
                                     target:self
                                     actions:[[CPBundleLocalizedString(@"Unplug", @"Unplug"), @selector(performDestroy:)], [CPBundleLocalizedString(@"Cancel", @"Cancel"), @selector(doNotPerformDestroy:)]]];

        [alert setShowsSuppressionButton:YES];
        [alert setUserInfo:alert];
        [alert runModal];
    }
    else
    {
        [self performDestroy:nil];
    }
}

/*! send destroy command
*/
- (void)performDestroy:(id)someUserInfo
{
    if (someUserInfo)
    {
        // remove the cyclic reference
        [someUserInfo setUserInfo:nil];

        if ([[someUserInfo suppressionButton] state] == CPOnState)
            [[CPUserDefaults standardUserDefaults] setBool:YES forKey:@"TNArchipelTypeVirtualMachineControlDoNotShowDestroyAlert"];
    }

    var stanza  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlDestroy}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didDestroy:)];
}

/*! cancel destroy
*/
- (void)doNotPerformDestroy:(id)someUserInfo
{
    [self layoutButtons:_VMLibvirtStatus];
}

/*! compute the destroy result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didDestroy:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [buttonScreenshot setImage:_imageScreenShutDown];
        if (_screenshotTimer)
        {
            [_screenshotTimer invalidate];
            _screenshotTimer = nil;
        }
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine has been destroyed.", @"Virtual machine has been destroyed.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send reboot command
*/
- (void)reboot
{
    var stanza  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlReboot}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didReboot:)];
}

/*! compute the reboot result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didReboot:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine is rebooting.", @"Virtual machine is rebooting.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send autostart command
*/
- (void)setAutostart
{
    var stanza      = [TNStropheStanza iqWithType:@"set"],
        autostart   = [switchAutoStart isOn] ? "1" : "0";

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlAutostart,
        "value": autostart}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didSetAutostart:)];
}

/*! compute the reboot result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didSetAutostart:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        if ([switchAutoStart isOn])
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"Autostart has been set.", @"Autostart has been set.")];
        else
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"Autostart has been unset.", @"Autostart has been unset.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}


/*! get OOM killer adjust value
*/
- (void)getOOMKiller
{
    var stanza      = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineOOM}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineOOMGetAdjust}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didGetOOMKiller:)];
}

/*! compute the oom prevention result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didGetOOMKiller:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var adjustValue = [[[aStanza firstChildWithName:@"oom"] valueForAttribute:@"adjust"] intValue],
            scoreValue  = [[[aStanza firstChildWithName:@"oom"] valueForAttribute:@"score"] intValue];

        if (adjustValue == -17)
            [switchPreventOOMKiller setOn:YES animated:YES sendAction:NO];
        else
            [switchPreventOOMKiller setOn:NO animated:YES sendAction:NO];

        [fieldOOMScore setStringValue:scoreValue];
        [fieldOOMAdjust setStringValue:(adjustValue == -17) ? CPBundleLocalizedString(@"Prevented", @"Prevented") : adjustValue];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send prevent OOM killer command
*/
- (void)setPreventOOMKiller
{
    var stanza      = [TNStropheStanza iqWithType:@"set"],
        prevent     = [switchPreventOOMKiller isOn] ? "-17" : "0";

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineOOM}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineOOMSetAdjust,
        "adjust": prevent}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didSetPreventOOMKiller:)];
}

/*! compute the oom prevention result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didSetPreventOOMKiller:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        if ([switchPreventOOMKiller isOn])
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"OOM Killer cannot kill this virtual machine.", @"OOM Killer cannot kill this virtual machine.")];
        else
            [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                             message:CPBundleLocalizedString(@"OOM Killer can kill this virtual machine.", @"OOM Killer can kill this virtual machine.")];

        if ([self currentEntityHasPermission:@"oom_getadjust"])
            [self getOOMKiller];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}



/*! send memory command
*/
- (void)setMemory
{
    var stanza      = [TNStropheStanza iqWithType:@"set"],
        memory      = [sliderMemory intValue];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlMemory,
        "value": memory}];
    [self sendStanza:stanza andRegisterSelector:@selector(_didSetMemory:)];
}

/*! compute the memory result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didSetMemory:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"error")
    {
        [self handleIqErrorFromStanza:aStanza];
        [self getVirtualMachineInfo];
        if ([self currentEntityHasPermission:@"oom_getadjust"])
            [self getOOMKiller];
    }

    return NO;
}

/*! send vCPUs command
*/
- (void)setVCPUs
{
    var stanza      = [TNStropheStanza iqWithType:@"set"],
        cpus        = [stepperCPU doubleValue];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlVCPUs,
        "value": cpus}];
    [self sendStanza:stanza andRegisterSelector:@selector(_didSetVCPUs:)];
}

/*! compute the vCPUs result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didSetVCPUs:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"error")
    {
        [self handleIqErrorFromStanza:aStanza];
        [self getVirtualMachineInfo];
        if ([self currentEntityHasPermission:@"oom_getadjust"])
            [self getOOMKiller];
    }

    return NO;
}

/*! send migrate command. but ask for a user confirmation
*/
- (void)migrate
{
    if ([tableHypervisors numberOfSelectedRows] != 1)
        return;

    var destinationHypervisor   = [_datasourceHypervisors objectAtIndex:[tableHypervisors selectedRow]];

    if ([destinationHypervisor fullJID] == _currentHypervisorJID)
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"You can't migrate to the initial virtual machine's hypervisor.", @"You can't migrate to the initial virtual machine's hypervisor.")
                                                            icon:TNGrowlIconError];
        return
    }

    var alert = [TNAlert alertWithMessage:CPBundleLocalizedString(@"Are you sure you want to migrate this virtual machine ?", @"Are you sure you want to migrate this virtual machine ?")
                                informative:CPBundleLocalizedString(@"You may continue to use this machine while migrating", @"You may continue to use this machine while migrating")
                                 target:self
                                 actions:[[CPBundleLocalizedString(@"Migrate", @"Migrate"), @selector(performMigrate:)], [CPBundleLocalizedString(@"Cancel", @"Cancel"), nil]]];

    [alert setUserInfo:destinationHypervisor]
    [alert runModal];
}

/*! send migrate command
*/
- (void)performMigrate:(id)someUserInfo
{
    var destinationHypervisor   = someUserInfo,
        stanza                  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlMigrate,
        "hypervisorjid": [destinationHypervisor fullJID]}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didMigrate:)];
}

/*! compute the migrate result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didMigrate:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Migration has started.", @"Migration has started.")];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send free command. but ask for user confirmation
*/
- (void)free
{
    var alert = [TNAlert alertWithMessage:CPBundleLocalizedString(@"Kill virtual machine?", @"Kill virtual machine?")
                                informative:CPBundleLocalizedString(@"You will loose this virtual machine. It will be destroyed, send to a black hole and it will never come back again. Sure?", @"You will loose this virtual machine. It will be destroyed, send to a black hole and it will never come back again. Sure?")
                                 target:self
                                 actions:[[CPBundleLocalizedString(@"Kill", @"Kill"), @selector(performFree:)], [CPBundleLocalizedString(@"Cancel", @"Cancel"), nil]]];

    [alert runModal];
}

/*! send free command
*/
- (void)performFree:(id)someUserInfo
{
    var stanza  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineControlFree}];

    _virtualMachineToFree = _entity;
    [self sendStanza:stanza andRegisterSelector:@selector(_didFree:)];
}

/*! compute the free result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didFree:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [[[TNStropheIMClient defaultClient] roster] removeContact:_virtualMachineToFree];
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine killed.", @"Virtual machine killed.")];
        [[CPNotificationCenter defaultCenter] postNotificationName:TNArchipelRosterOutlineViewDeselectAll object:self];
        _virtualMachineToFree = nil;
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }

    return NO;
}

/*! send park command. but ask for user confirmation
*/
- (void)park
{
    var alert = [TNAlert alertWithMessage:CPBundleLocalizedString(@"Park virtual machine?", @"Park virtual machine?")
                                informative:CPLocalizedString(@"Do you want to park this virtual machine?", @"Do you want to park this virtual machine?")
                                 target:self
                                 actions:[[CPBundleLocalizedString(@"Park", @"Park"), @selector(performPark:)], [CPBundleLocalizedString(@"Cancel", @"Cancel"), nil]]];

    [alert runModal];
}

/*! send park command
*/
- (void)performPark:(id)someUserInfo
{
    var stanza  = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypeVirtualMachineVMParking}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypeVirtualMachineVMParkingPark,
        "force": @"True"}];

    [self sendStanza:stanza andRegisterSelector:@selector(_didPark:)];
}

/*! compute the park result
    @param aStanza TNStropheStanza containing the results
*/
- (BOOL)_didPark:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:[_entity nickname]
                                                         message:CPBundleLocalizedString(@"Virtual machine is parking.", @"Virtual machine is parking.")];
    else
        [self handleIqErrorFromStanza:aStanza];

    return NO;
}


#pragma mark -
#pragma mark Delegates

- (void)tableViewSelectionDidChange:(CPNotification)aNotification
{
    var selectedRow = [[tableHypervisors selectedRowIndexes] firstIndex];

    if (selectedRow == -1)
    {
        [_migrateButton setEnabled:NO];

        return
    }

    var item = [_datasourceHypervisors objectAtIndex:selectedRow];

    if ([item fullJID] != _currentHypervisorJID)
        [_migrateButton setEnabled:YES];
    else
        [_migrateButton setEnabled:NO];
}

- (void)imageDidLoad:(CPImage)anImage
{
    [buttonScreenshot setImage:anImage];

    if (!_screenshotTimer && [self isVisible])
    {
        var defaults = [CPUserDefaults standardUserDefaults];
        _screenshotTimer = [CPTimer scheduledTimerWithTimeInterval:[defaults integerForKey:@"TNArchipelControlsScreenshotRefresh"]
                                                            target:self
                                                          selector:@selector(getThumbnailScreenshot:)
                                                          userInfo:nil
                                                           repeats:NO];
    }
}

@end


// add this code to make the CPLocalizedString looking at
// the current bundle.
function CPBundleLocalizedString(key, comment)
{
    return CPLocalizedStringFromTableInBundle(key, nil, [CPBundle bundleForClass:TNVirtualMachineControlsController], comment);
}

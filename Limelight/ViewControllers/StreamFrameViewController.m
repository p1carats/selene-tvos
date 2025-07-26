//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import AVFoundation.AVDisplayCriteria;
@import AVKit.AVDisplayManager;
@import AVKit.UIWindow;
@import GameStreamKit;

#import "StreamFrameViewController.h"
#import "MetalViewController.h"
#import "StreamManager.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "StreamConfiguration.h"
#import "PaddedLabel.h"
#import "SceneDelegate.h"
#import "Logger.h"
#import "Connection.h"

@interface AVDisplayCriteria()

@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (instancetype)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;

@end

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    PaddedLabel *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    PlotMetrics _decodeMetrics;
    PlotMetrics _frameDropMetrics;
    PlotMetrics _frameQueueMetrics;

    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseDoubleTapGestureRecognizer;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)controllerPauseButtonPressed:(id)sender { }

- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}

- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- toggling stats");
    if (!self->_statsUpdateTimer) {
        [self showStats];
    } else {
        [self hideStats];
    }
}

- (void)controllerPlayPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Play/Pause button double-tapped -- backing out of stream");
    [self returnToMainFrame];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];

    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleLarge];
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer || !_playPauseDoubleTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _playPauseDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonDoublePressed:)];
        _playPauseDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        _playPauseDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        [_playPauseTapGestureRecognizer requireGestureRecognizerToFail:_playPauseDoubleTapGestureRecognizer];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseDoubleTapGestureRecognizer];

    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    [_streamView setupStreamView:_controllerSupport
             interactionDelegate:self
                          config:self.streamConfig];

    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote for stats. Double-click to disconnect from your PC."];
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sceneWillResignActive:)
                                                 name:UISceneWillDeactivateNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(sceneDidBecomeActive:)
                                                 name: UISceneDidActivateNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(sceneDidEnterBackground:)
                                                 name: UISceneDidEnterBackgroundNotification
                                               object: nil];
    
    // Add StreamView directly in relative mode
    [self.view addSubview:_streamView];
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];

    if ([_settings.renderingBackend intValue] == RenderingBackendMetal) {
        // Metal view for video
        self.metalViewController = [[MetalViewController alloc] initWithFrame:self.view.bounds
                                                                    framerate:[self->_settings.framerate floatValue]
                                                                    enableHdr:self->_settings.enableHdr
                                                               metricsHandler:self.graphRenderer.metricsHandler];
        self.metalViewController.view.userInteractionEnabled = NO;
        [self.view addSubview:self.metalViewController.view];
        [self.view bringSubviewToFront:self.metalViewController.view];
    }

    // Make a view for the graphs
    self.graphRenderer = [[GraphRenderer alloc] initWithFrame:self.view.bounds
                                                streamFps:[_settings.framerate intValue]
                                             enableGraphs:_settings.enableGraphs
                                             graphOpacity:[_settings.graphOpacity intValue]];
    self.graphRenderer.view.userInteractionEnabled = NO;
    [self.view addSubview:self.graphRenderer.view];
    [self.view bringSubviewToFront:self.graphRenderer.view];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[PaddedLabel alloc] initWithFrame:CGRectZero];
        [_overlayView setTextInsets:UIEdgeInsetsMake(10, 15, 10, 15)];
        [_overlayView setUserInteractionEnabled:YES];
        [_overlayView setNumberOfLines:100];
        [_overlayView.layer setCornerRadius:12];
        [_overlayView.layer setMasksToBounds:YES];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
        [_overlayView setFont:[UIFont systemFontOfSize:24 weight:UIFontWeightMedium]];
        int opacity = MAX([_settings.graphOpacity intValue], 60);
        [_overlayView setAlpha:(float)opacity / 100.0];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, (12 + (_overlayView.frame.size.height / 2)))];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;

    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if scene becomes inactive (maybe control center on tvOS but not sure this is relevant?)
- (void)sceneWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)sceneDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the scene enters the background (likely home screen)
- (void)sceneDidEnterBackground:(NSNotification *)notification {
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)edgeSwiped {
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

- (void)topSwiped {
    Log(LOG_I, @"User swiped/cicked down for stats");
    [self showStats];
}

- (void)showStats {
    if (self->_statsUpdateTimer == nil) {
        self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                   target:self
                                                                 selector:@selector(updateStatsOverlay)
                                                                 userInfo:nil
                                                                  repeats:YES];
        [self->_statsUpdateTimer fire];

        if (_settings.enableGraphs) {
            [self.graphRenderer start];
            [self.graphRenderer show];
        }
    }
}

- (void)topSwipedUp {
    Log(LOG_I, @"User swiped up to hide stats");
    [self hideStats];
}

- (void)hideStats {
    if (self->_statsUpdateTimer != nil) {
        [_statsUpdateTimer invalidate];
        _statsUpdateTimer = nil;
    }

    if (_overlayView != nil) {
        [_overlayView setHidden:YES];
    }

    if (_settings.enableGraphs) {
        [self.graphRenderer hide];
        [self.graphRenderer stop];
    }
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            [self topSwiped];
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Selene. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Selene. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void)applicationDidFinishSwitchingModes:(NSNotification *)notification {
    // Check the current refresh rate of the TV for a fractional NTSC rate such as 59.94
    // UIScreen *screen = [UIScreen mainScreen];
    // XXX: I can see screen.currentMode.refreshRate in the debugger, but don't know how to access it :(

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVDisplayManagerModeSwitchEndNotification
                                                  object:nil];
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
    SceneDelegate *sceneDelegate = [SceneDelegate sharedSceneDelegate];
    AVDisplayManager* displayManager = [sceneDelegate.window avDisplayManager];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishSwitchingModes:)
                                                 name:AVDisplayManagerModeSwitchEndNotification
                                               object:nil];
    
    // This logic comes from Kodi and MrMC
    if (streamActive) {
        int dynamicRange = LiGetCurrentHostDisplayHdrMode() ? 2 : 0; // 2 for HDR10, 0 for SDR
        
        float refreshRate = [_settings.framerate floatValue];
        Log(LOG_I, @"Changing TV refresh rate to %f Hz %@", refreshRate, dynamicRange == 2 ? @"HDR" : @"SDR");
        AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:refreshRate
                                                                          videoDynamicRange:dynamicRange];
        displayManager.preferredDisplayCriteria = displayCriteria;
    }
    else {
        // Switch back to the default display mode
        displayManager.preferredDisplayCriteria = nil;
    }
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable user interaction handling when user is interacting
    _userIsInteracting = YES;
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
}

@end

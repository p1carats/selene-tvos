//
//  UIAppView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIAppView.h"
#import "AppAssetManager.h"
#import "TemporaryApp.h"
#import "TemporaryHost.h"

static const float REFRESH_CYCLE = 1.0f;

@implementation UIAppView {
    TemporaryApp* _app;
    UILabel* _appLabel;
    UIImageView* _appOverlay;
    UIImageView* _appImage;
    NSCache* _artCache;
    id<AppCallback> _callback;
}

static UIImage* noImage;

- (instancetype) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback {
    self = [super init];
    _app = app;
    _callback = callback;
    _artCache = cache;
    
    // Cache the NoAppImage ourselves to avoid
    // having to load it each time
    if (noImage == nil) {
        noImage = [UIImage imageNamed:@"NoAppImage"];
    }
    
    self.frame = CGRectMake(0, 0, 200, 265);
    
    [self setAlpha:app.hidden ? 0.4 : 1.0];
    
    _appImage = [[UIImageView alloc] initWithFrame:self.frame];
    [_appImage setImage:noImage];
    [self addSubview:_appImage];
    
    UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appLongClicked:)];
    [self addGestureRecognizer:longPressRecognizer];
    
    [self addTarget:self action:@selector(appClicked:) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [self addTarget:self action:@selector(buttonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(buttonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
    _appImage.adjustsImageWhenAncestorFocused = YES;
    
    [self updateAppImage];
    
    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil) {
        [self updateLoop];
    }
}

- (void) appClicked:(UIView *)view {
    [_callback appClicked:_app view:view];
}

- (void) appLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback appLongClicked:_app view:self];
    }
}

- (void) updateAppImage {
    if (_appOverlay != nil) {
        [_appOverlay removeFromSuperview];
        _appOverlay = nil;
    }
    if (_appLabel != nil) {
        [_appLabel removeFromSuperview];
        _appLabel = nil;
    }
    
    BOOL noAppImage = false;
    
    // First check the memory cache
    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        // Next try to load from the on disk cache
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }
    
    if (appImage != nil) {
        // This size of image might be blank image received from GameStream.
        // TODO: Improve no-app image detection
        if (!(appImage.size.width == 130.f && appImage.size.height == 180.f) && // GFE 2.0
            !(appImage.size.width == 628.f && appImage.size.height == 888.f)) { // GFE 3.0
            [_appImage setImage:appImage];
        } else {
            noAppImage = true;
        }
    } else {
        noAppImage = true;
    }
    
    if ([_app.id isEqualToString:_app.host.currentGame]) {
        // Only create the app overlay if needed
        _appOverlay = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill"]];
        _appOverlay.tintColor = [UIColor grayColor];
        _appOverlay.layer.shadowColor = [UIColor blackColor].CGColor;
        _appOverlay.layer.shadowOffset = CGSizeMake(0, 0);
        _appOverlay.layer.shadowOpacity = 1;
        _appOverlay.layer.shadowRadius = 4.0;
        _appOverlay.contentMode = UIViewContentModeScaleAspectFit;
    }
    
    if (noAppImage) {
        _appLabel = [[UILabel alloc] init];
        [_appLabel setTextColor:[UIColor whiteColor]];
        [_appLabel setText:_app.name];
        [_appLabel setFont:[UIFont systemFontOfSize:24]];
        [_appLabel setBaselineAdjustment:UIBaselineAdjustmentAlignCenters];
        [_appLabel setTextAlignment:NSTextAlignmentCenter];
        [_appLabel setLineBreakMode:NSLineBreakByWordWrapping];
        [_appLabel setNumberOfLines:0];
    }
    
    [self positionSubviews];
    
    [_appImage.overlayContentView addSubview:_appLabel];
    [_appImage.overlayContentView addSubview:_appOverlay];
}

- (void) buttonSelected:(id)sender {
    _appImage.layer.opacity = 0.5f;
}
- (void) buttonDeselected:(id)sender {
    _appImage.layer.opacity = 1.0f;
}

- (void) positionSubviews {
    CGFloat padding = 5.f;
    CGSize frameSize = _appImage.frame.size;
    CGPoint center = _appImage.center;
    
    if (_appLabel != nil) {
        if (_appOverlay != nil) {
            _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 3, frameSize.width / 3);
            _appOverlay.center = CGPointMake(frameSize.width / 2, padding + _appOverlay.frame.size.height / 2);
            
            [_appLabel setFrame:CGRectMake(padding, _appOverlay.frame.size.height + padding, frameSize.width - 2 * padding, frameSize.height - _appOverlay.frame.size.height - 2 * padding)];
        }
        else {
            [_appLabel setFrame:CGRectMake(padding, padding, frameSize.width - 2 * padding, frameSize.height - 2 * padding)];
        }
    }
    else if (_appOverlay != nil) {
        _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 2, frameSize.width / 2);
        _appOverlay.center = center;
    }
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }
    
    // Update the app image if neccessary
    if ((_appOverlay != nil && ![_app.id isEqualToString:_app.host.currentGame]) ||
        (_appOverlay == nil && [_app.id isEqualToString:_app.host.currentGame])) {
        [self updateAppImage];
    }
    
    // Show no shadow for hidden apps. Because we adjust the opacity of the
    // cells for hidden apps, it makes them look bad when the shadow draws
    // through the app tile.
    self.superview.layer.shadowOpacity = _app.hidden ? 0.0f : 0.5f;
    
    // Update opacity if neccessary
    [self setAlpha:_app.hidden ? 0.4 : 1.0];
    
    // Queue the next refresh cycle
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(REFRESH_CYCLE * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateLoop];
    });
}

@end

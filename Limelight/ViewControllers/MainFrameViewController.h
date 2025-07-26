//
//  MainFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/17/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import UIKit;

#import "DiscoveryManager.h"
#import "PairManager.h"
#import "UIComputerView.h"
#import "UIAppView.h"
#import "AppAssetManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface MainFrameViewController : UICollectionViewController <DiscoveryCallback, PairCallback, HostCallback, AppCallback, AppAssetCallback>

@property (weak, nonatomic) IBOutlet UIBarButtonItem *settingsButton;

@end

NS_ASSUME_NONNULL_END

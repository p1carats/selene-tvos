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

@interface MainFrameViewController : UICollectionViewController <DiscoveryCallback, PairCallback, HostCallback, AppCallback, AppAssetCallback, NSURLConnectionDelegate>

@property (weak, nonatomic) IBOutlet UIBarButtonItem *settingsButton;

@end

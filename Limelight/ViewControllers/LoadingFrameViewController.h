//
//  LoadingFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/24/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface LoadingFrameViewController : UIViewController

- (void)showLoadingFrame:(void (^)(void))completion;

- (void)dismissLoadingFrame:(void (^)(void))completion;

- (BOOL)isShown;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingSpinner;

@end

NS_ASSUME_NONNULL_END

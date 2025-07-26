//
//  SceneDelegate.h
//  Selene
//
//  Created by Noé Barlet on 26/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

+ (SceneDelegate *)sharedSceneDelegate;

@end

NS_ASSUME_NONNULL_END

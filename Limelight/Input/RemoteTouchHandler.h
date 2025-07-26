//
//  RemoteTouchHandler.h
//  Selene
//
//  Created by Noé Barlet on 26/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@class StreamView;

@interface RemoteTouchHandler : NSObject

@property (nonatomic) UITapGestureRecognizer* remotePressRecognizer;
@property (nonatomic) float mouseSensitivity;

-(instancetype)initWithView:(StreamView*)view streamWidth:(int)width streamHeight:(int)height;

@end

NS_ASSUME_NONNULL_END

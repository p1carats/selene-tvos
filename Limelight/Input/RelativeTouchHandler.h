//
//  RelativeTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

@import Foundation;
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@class StreamView;

@interface RelativeTouchHandler : UIResponder

@property (nonatomic) UIGestureRecognizer* remotePressRecognizer;
@property (nonatomic) UIGestureRecognizer* remoteLongPressRecognizer;

-(instancetype)initWithView:(StreamView*)view;

@end

NS_ASSUME_NONNULL_END

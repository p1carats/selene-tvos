//
//  RelativeTouchHandler.h
//  Selene
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class StreamView;

@interface RelativeTouchHandler : NSObject

@property (nonatomic) UITapGestureRecognizer* remotePressRecognizer;
@property (nonatomic) UILongPressGestureRecognizer* remoteLongPressRecognizer;

-(id)initWithView:(StreamView*)view;

@end

NS_ASSUME_NONNULL_END

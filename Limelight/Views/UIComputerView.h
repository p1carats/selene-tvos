//
//  UIComputerView.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import UIKit;

@class TemporaryHost;

@protocol HostCallback <NSObject>

- (void) hostClicked:(TemporaryHost*)host view:(UIView*)view;
- (void) hostLongClicked:(TemporaryHost*)host view:(UIView*)view;
- (void) addHostClicked;

@end

@interface UIComputerView : UIButton

- (instancetype) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback;
- (instancetype) initForAddWithCallback:(id<HostCallback>)callback;

@end

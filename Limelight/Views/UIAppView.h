//
//  UIAppView.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import UIKit;

@class TemporaryApp;

@protocol AppCallback <NSObject>

- (void) appClicked:(TemporaryApp*)app view:(UIView*)view;
- (void) appLongClicked:(TemporaryApp*)app view:(UIView*)view;

@end

@interface UIAppView : UIButton

- (id) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback;
- (void) updateAppImage;

@end

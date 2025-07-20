//
//  GraphView.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface GraphView : UIView

@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *unit;
@property (nonatomic, assign) int labelType;
@property (nonatomic, assign) float scaleMin;
@property (nonatomic, assign) float scaleMax;
@property (nonatomic, assign) float scaleTarget;
@property (nonatomic, assign) float opacity;

- (void)updateWithValues:(const float *)values 
                   count:(int)count 
                 minimum:(float)minimum 
                 maximum:(float)maximum 
                 average:(float)average
                   total:(float)total;

@end

NS_ASSUME_NONNULL_END 

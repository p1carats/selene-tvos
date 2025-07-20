//
//  PlotDefinition.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class FloatBuffer;

@interface PlotDefinition : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, assign) int side;
@property (nonatomic, assign) int labelType;
@property (nonatomic, assign) float scaleMin;
@property (nonatomic, assign) float scaleMax;
@property (nonatomic, assign) float scaleTarget;
@property (nonatomic, strong) FloatBuffer *buffer;

- (instancetype)initWithTitle:(NSString *)title
                         unit:(NSString *)unit
                         side:(int)side
                    labelType:(int)labelType
                     scaleMin:(float)scaleMin
                     scaleMax:(float)scaleMax
                  scaleTarget:(float)scaleTarget;

@end

NS_ASSUME_NONNULL_END

//
//  PlotDefinition.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

#import "PlotDefinition.h"
#import "FloatBuffer.h"

@implementation PlotDefinition

- (instancetype)initWithTitle:(NSString *)title
                         unit:(NSString *)unit
                         side:(int)side
                    labelType:(int)labelType
                     scaleMin:(float)scaleMin
                     scaleMax:(float)scaleMax
                  scaleTarget:(float)scaleTarget {
    self = [super init];
    if (self) {
        _title = [title copy];
        _unit = [unit copy];
        _side = side;
        _labelType = labelType;
        _scaleMin = scaleMin;
        _scaleMax = scaleMax;
        _scaleTarget = scaleTarget;
        _buffer = [[FloatBuffer alloc] initWithCapacity:512];
    }
    return self;
}

@end

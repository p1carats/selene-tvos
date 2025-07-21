//
//  ComputerScrollView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 9/30/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "ComputerScrollView.h"

@implementation ComputerScrollView

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    if ([view isKindOfClass:[UIButton class]]) {
        return YES;
    }
    return [super touchesShouldCancelInContentView:view];
}

@end

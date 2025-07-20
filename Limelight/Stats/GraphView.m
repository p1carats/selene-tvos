//
//  GraphView.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import QuartzCore;

#import "GraphView.h"
#import "Plot.h"

@interface GraphView ()
@property (nonatomic, strong) NSMutableArray<NSNumber *> *plotValues;
@property (nonatomic, assign) float currentMin;
@property (nonatomic, assign) float currentMax;
@property (nonatomic, assign) float currentAvg;
@property (nonatomic, assign) float currentTotal;
@property (nonatomic, assign) int currentCount;
@property (nonatomic, strong) NSAttributedString *cachedLabelText;
@property (nonatomic, strong) NSDictionary *labelAttributes;
@end

@implementation GraphView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.plotValues = [NSMutableArray array];
        self.scaleMin = MAXFLOAT;
        self.scaleMax = MAXFLOAT;
        self.scaleTarget = 0;
        self.opacity = 1.0f;
        
        // Enable high-quality drawing
        self.layer.contentsScale = [UIScreen mainScreen].scale;
        self.contentScaleFactor = [UIScreen mainScreen].scale;
        
        // Cache label attributes
        _labelAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont systemFontOfSize:12]
        };
    }
    return self;
}

- (void)updateWithValues:(const float *)values
                   count:(int)count
                 minimum:(float)minimum
                 maximum:(float)maximum
                 average:(float)average
                   total:(float)total {
    
    [self.plotValues removeAllObjects];
    for (int i = 0; i < count; i++) {
        [self.plotValues addObject:@(values[i])];
    }
    
    self.currentMin = minimum;
    self.currentMax = maximum;
    self.currentAvg = average;
    self.currentTotal = total;
    self.currentCount = count;
    
    self.cachedLabelText = nil;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (self.currentCount == 0) return;
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    
    // Clear the background
    CGContextClearRect(context, rect);
    
    // Draw background with opacity
    CGContextSetFillColorWithColor(context, [UIColor colorWithRed:0.16f green:0.29f blue:0.48f alpha:self.opacity].CGColor);
    CGContextFillRect(context, rect);
    
    // Calculate graph area (leave space for label)
    CGRect graphRect = CGRectMake(4, 16, rect.size.width - 8, rect.size.height - 20);
    
    if (self.plotValues.count < 2) return;
    
    // Calculate scale
    float scaleMin = self.scaleMin;
    float scaleMax = self.scaleMax;
    
    if (scaleMin == MAXFLOAT || scaleMax == MAXFLOAT) {
        if (self.scaleTarget > 0) {
            float ideal = self.scaleTarget;
            scaleMin = ideal - (2 * ideal);
            scaleMax = ideal + (2 * ideal);
        } else {
            scaleMin = self.currentMin;
            scaleMax = self.currentMax;
        }
    }
    
    // Ensure we have a valid range
    if (scaleMax <= scaleMin) {
        scaleMax = scaleMin + 1.0f;
    }
    
    // Draw the graph line
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f].CGColor);
    CGContextSetLineWidth(context, 1.0f);
    
    CGContextBeginPath(context);
    
    BOOL firstPoint = YES;
    for (int i = 0; i < self.plotValues.count; i++) {
        float value = [self.plotValues[i] floatValue];
        
        // Clip frametime values
        if ([self.title isEqualToString:@"Frametime"] || [self.title isEqualToString:@"Host Frametime"]) {
            if (value > 50) {
                value = 49.9f;
            }
        }
        
        float x = graphRect.origin.x + (i * graphRect.size.width / (self.plotValues.count - 1));
        float normalizedValue = (value - scaleMin) / (scaleMax - scaleMin);
        normalizedValue = MAX(0, MIN(1, normalizedValue)); // Clamp to [0,1]
        float y = graphRect.origin.y + graphRect.size.height - (normalizedValue * graphRect.size.height);
        
        if (firstPoint) {
            CGContextMoveToPoint(context, x, y);
            firstPoint = NO;
        } else {
            CGContextAddLineToPoint(context, x, y);
        }
    }
    
    CGContextStrokePath(context);
    
    // Draw the label
    [self drawLabel:context rect:rect];
}

- (void)drawLabel:(CGContextRef)context rect:(CGRect)rect {
    NSString *labelText = [self formatLabel];
    
    if (!self.cachedLabelText || ![self.cachedLabelText.string isEqualToString:labelText]) {
        self.cachedLabelText = [[NSAttributedString alloc] initWithString:labelText attributes:self.labelAttributes];
    }
    
    // Draw at top left
    CGRect labelRect = CGRectMake(4, 2, rect.size.width - 8, 14);
    [self.cachedLabelText drawInRect:labelRect];
}

- (NSString *)formatLabel {
    if (self.currentCount == 0) {
        return @"No data";
    }
    
    switch (self.labelType) {
        case PlotLabelTypeMinMaxAverage:
            return [NSString stringWithFormat:@"%@  %.1f/%.1f/%.1f %@",
                    self.title, self.currentMin, self.currentMax, self.currentAvg, self.unit];
            
        case PlotLabelTypeMinMaxAverageInt:
            return [NSString stringWithFormat:@"%@  %d/%d/%.1f %@",
                    self.title, (int)self.currentMin, (int)self.currentMax, self.currentAvg, self.unit];
            
        case PlotLabelTypeTotalInt:
            return [NSString stringWithFormat:@"%@  %d %@",
                    self.title, (int)self.currentTotal, self.unit];
            
        default:
            return [NSString stringWithFormat:@"%@  %.1f %@", self.title, self.currentAvg, self.unit];
    }
}

@end

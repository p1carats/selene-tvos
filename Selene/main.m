//
//  main.m
//  Selene
//
//  Created by Noé Barlet on 14/08/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import UIKit;

#import "AppDelegate.h"

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}

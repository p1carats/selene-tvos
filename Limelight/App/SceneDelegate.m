//
//  SceneDelegate.m
//  Selene
//
//  Created by Noé Barlet on 26/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

#import "SceneDelegate.h"
#import "Logger.h"

@implementation SceneDelegate

+ (SceneDelegate *)sharedSceneDelegate {
    UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
    return (SceneDelegate *)windowScene.delegate;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
    // If using a storyboard, the `window` property will automatically be configured and attached to the scene.
    // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
    
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    
    // The window will be automatically configured if using a storyboard
    if (!self.window) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        self.window.rootViewController = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateInitialViewController];
        [self.window makeKeyAndVisible];
    }
    
    Log(LOG_I, @"Scene connected to session");
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    Log(LOG_I, @"Scene disconnected");
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    Log(LOG_I, @"Scene became active");
    
    // Post scene-based notifications for view controllers to observe
    [[NSNotificationCenter defaultCenter] postNotificationName:UISceneDidActivateNotification object:scene];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
    Log(LOG_I, @"Scene will resign active");
    
    // Post scene-based notifications for view controllers to observe
    [[NSNotificationCenter defaultCenter] postNotificationName:UISceneWillDeactivateNotification object:scene];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo many of the changes made on entering the background.
    Log(LOG_I, @"Scene will enter foreground");
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
    Log(LOG_I, @"Scene entered background");
}

@end

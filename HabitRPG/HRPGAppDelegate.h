//
//  HRPGAppDelegate.h
//  HabitRPG
//
//  Created by Phillip Thelen on 08/03/14.
//  Copyright (c) 2014 Phillip Thelen. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "HRPGManager.h"

@protocol OIDAuthorizationFlowSession;

@interface HRPGAppDelegate : UIResponder<UIApplicationDelegate, UIAlertViewDelegate>

@property(strong, nonatomic, nullable) UIWindow *window;
@property(strong, nonatomic, nullable) HRPGManager *sharedManager;

@property(nonatomic, strong, nullable)id<OIDAuthorizationFlowSession> currentAuthorizationFlow;
@end

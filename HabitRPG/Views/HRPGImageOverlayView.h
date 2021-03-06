//
//  HRPGPetHatchedOverlayView.h
//  Habitica
//
//  Created by Phillip on 10/07/14.
//  Copyright (c) 2014 Phillip Thelen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KLCPopup.h"

@interface HRPGImageOverlayView : UIView<UIGestureRecognizerDelegate>

- (void)displayImageWithName:(NSString *)imageName;
- (void)displayImage:(UIImage *)image;
- (void)setAchievementWithName:(NSString *)achievementName;

@property(nonatomic) CGFloat imageHeight;
@property(nonatomic) CGFloat imageWidth;

@property(nonatomic) NSString *titleText;
@property(nonatomic) NSString *descriptionText;

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIImageView *leftAchievementView;
@property (weak, nonatomic) IBOutlet UIImageView *rightAchievementView;

@property(nonatomic) NSString *dismissButtonText;
@property(nonatomic) void (^dismissAction)();
@property(nonatomic) void (^shareAction)();

@end

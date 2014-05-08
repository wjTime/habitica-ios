    //
//  HRPGManager.m
//  HabitRPG
//
//  Created by Phillip Thelen on 09/03/14.
//  Copyright (c) 2014 Phillip Thelen. All rights reserved.
//

#import "HRPGManager.h"
#import "Task.h"
#import "user.h"
#import "CRToast.h"
#import "HRPGTaskResponse.h"
#import "HRPGLoginData.h"
#import <PDKeychainBindings.h>
#import <NIKFontAwesomeIconFactory.h>
#import <NIKFontAwesomeIconFactory+iOS.h>
#import "Gear.h"
#import "Egg.h"
#import "Group.h"
#import "Item.h"
#import <SDWebImageManager.h>
#import <SDImageCache.h>
#import "HRPGUserBuyResponse.h"

@implementation HRPGManager
@synthesize managedObjectContext;
RKManagedObjectStore *managedObjectStore;
User *user;
NSUserDefaults *defaults;
NSString *currentUser;
NIKFontAwesomeIconFactory *iconFactory;

+(RKValueTransformer*)millisecondsSince1970ToDateValueTransformer {
    return [RKBlockValueTransformer valueTransformerWithValidationBlock:^BOOL(__unsafe_unretained Class sourceClass, __unsafe_unretained Class destinationClass) {
        return [sourceClass isSubclassOfClass:[NSNumber class]] && [destinationClass isSubclassOfClass:[NSDate class]];
    } transformationBlock:^BOOL(id inputValue, __autoreleasing id *outputValue, __unsafe_unretained Class outputValueClass, NSError *__autoreleasing *error) {
        RKValueTransformerTestInputValueIsKindOfClass(inputValue, (@[ [NSNumber class] ]), error);
        RKValueTransformerTestOutputValueClassIsSubclassOfClass(outputValueClass, (@[ [NSDate class] ]), error);
        *outputValue = [NSDate dateWithTimeIntervalSince1970:([inputValue longLongValue] / 1000)];
        return YES;
    }];
}

-(void)loadObjectManager
{
    NSError *error = nil;
    NSURL *modelURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"HabitRPG" ofType:@"momd"]];
    // NOTE: Due to an iOS 5 bug, the managed object model returned is immutable.
    NSManagedObjectModel *managedObjectModel = [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] mutableCopy];
    managedObjectStore = [[RKManagedObjectStore alloc] initWithManagedObjectModel:managedObjectModel];
    
    // Initialize the Core Data stack
    [managedObjectStore createPersistentStoreCoordinator];
    
    NSString *storePath = [RKApplicationDataDirectory() stringByAppendingPathComponent:@"HabitRPG.sqlite"];
    NSPersistentStore *persistentStore = [managedObjectStore addSQLitePersistentStoreAtPath:storePath fromSeedDatabaseAtPath:nil withConfiguration:nil options:nil error:&error];
    NSAssert(persistentStore, @"Failed to add persistent store with error: %@", error);
    
    // Create the managed object contexts
    [managedObjectStore createManagedObjectContexts];
    
    // Configure a managed object cache to ensure we do not create duplicate objects
    managedObjectStore.managedObjectCache = [[RKInMemoryManagedObjectCache alloc] initWithManagedObjectContext:managedObjectStore.persistentStoreManagedObjectContext];
    
    // Set the default store shared instance
    [RKManagedObjectStore setDefaultStore:managedObjectStore];
    RKObjectManager *objectManager = [RKObjectManager managerWithBaseURL:[NSURL URLWithString:@"https://habitrpg.com"]];
    objectManager.managedObjectStore = managedObjectStore;
    
    [RKObjectManager setSharedManager:objectManager];
    [RKObjectManager sharedManager].requestSerializationMIMEType = RKMIMETypeJSON;
    [objectManager.HTTPClient setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        if (status == AFNetworkReachabilityStatusNotReachable) {
            NSDictionary *options = @{kCRToastTextKey : NSLocalizedString(@"No Network connection", nil),
                                      kCRToastSubtitleTextKey :NSLocalizedString(@"You need a network connection to do that.", nil),
                                      kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                                      kCRToastBackgroundColorKey : [UIColor colorWithRed:1.0f green:0.22f blue:0.22f alpha:1.0f]};
            [CRToastManager showNotificationWithOptions:options
                                        completionBlock:^{
                                        }];
            
        }
    }];
    
    RKValueTransformer* transformer = [HRPGManager millisecondsSince1970ToDateValueTransformer];
    [[RKValueTransformer defaultValueTransformer] insertValueTransformer:transformer atIndex:0];
    
    RKEntityMapping *taskMapping = [RKEntityMapping mappingForEntityForName:@"Task" inManagedObjectStore:managedObjectStore];
    [taskMapping addAttributeMappingsFromDictionary:@{
                                                        @"id": @"id",
                                                        @"attribute" : @"attribute",
                                                        @"down" : @"down",
                                                        @"up" : @"up",
                                                        @"priority" : @"priority",
                                                        @"text" : @"text",
                                                        @"value" : @"value",
                                                        @"type" : @"type",
                                                        @"completed" : @"completed",
                                                        @"notes" : @"notes",
                                                        @"streak" : @"streak",
                                                        @"dateCreated" : @"dateCreated",
                                                        @"repeat.m": @"monday",
                                                        @"repeat.t": @"tuesday",
                                                        @"repeat.w": @"wednesday",
                                                        @"repeat.th": @"thursday",
                                                        @"repeat.f": @"friday",
                                                        @"repeat.s": @"saturday",
                                                        @"repeat.su": @"sunday",
                                                        @"@metadata.mapping.collectionIndex" : @"order"}];
    taskMapping.identificationAttributes = @[ @"id" ];
    RKEntityMapping* checklistItemMapping = [RKEntityMapping mappingForEntityForName:@"ChecklistItem" inManagedObjectStore:managedObjectStore];
    [checklistItemMapping addAttributeMappingsFromArray:@[@"id", @"text", @"completed"]];
    checklistItemMapping.identificationAttributes = @[ @"id", @"text" ];

    [taskMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"checklist"
                                                                                  toKeyPath:@"checklist"
                                                                                withMapping:checklistItemMapping]];
    
    RKResponseDescriptor *responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodGET pathPattern:@"/api/v2/user/tasks" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    [[RKObjectManager sharedManager].router.routeSet addRoute:[RKRoute routeWithClass:[Task class] pathPattern:@"/api/v2/user/tasks/:id" method:RKRequestMethodGET]];
    [[RKObjectManager sharedManager].router.routeSet addRoute:[RKRoute routeWithClass:[Task class] pathPattern:@"/api/v2/user/tasks/:id" method:RKRequestMethodPUT]];
    [[RKObjectManager sharedManager].router.routeSet addRoute:[RKRoute routeWithClass:[Task class] pathPattern:@"/api/v2/user/tasks" method:RKRequestMethodPOST]];
    [[RKObjectManager sharedManager].router.routeSet addRoute:[RKRoute routeWithClass:[Task class] pathPattern:@"/api/v2/user/tasks/:id" method:RKRequestMethodDELETE]];
    
    RKObjectMapping *taskRequestMapping = [RKObjectMapping mappingForClass:[NSMutableDictionary class] ];
    [taskRequestMapping addAttributeMappingsFromDictionary:@{
                                                        @"id": @"id",
                                                        @"attribute" : @"attribute",
                                                        @"down" : @"down",
                                                        @"up" : @"up",
                                                        @"priority" : @"priority",
                                                        @"text" : @"text",
                                                        @"value" : @"value",
                                                        @"type" : @"type",
                                                        @"completed" : @"completed",
                                                        @"notes" : @"notes",
                                                        @"streak" : @"streak",
                                                        @"dateCreated" : @"dateCreated",
                                                        @"monday" : @"repeat.m",
                                                        @"tuesday" : @"repeat.t",
                                                        @"wednesday" : @"repeat.w",
                                                        @"thursday" : @"repeat.th",
                                                        @"friday" : @"repeat.f",
                                                        @"saturday" : @"repeat.s",
                                                        @"sunday" : @"repeat.su"}];
    RKObjectMapping *checklistItemRequestMapping = [RKObjectMapping mappingForClass:[NSMutableDictionary class]];
    [checklistItemRequestMapping addAttributeMappingsFromArray:@[@"id", @"text", @"completed"]];
    [taskRequestMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"checklist"
                                                                                toKeyPath:@"checklist"
                                                                              withMapping:checklistItemRequestMapping]];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodPUT pathPattern:@"/api/v2/user/tasks/:id" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    RKRequestDescriptor *requestDescriptor = [RKRequestDescriptor requestDescriptorWithMapping:taskRequestMapping objectClass:[Task class] rootKeyPath:nil method:RKRequestMethodPUT];
    [objectManager addResponseDescriptor:responseDescriptor];
    [objectManager addRequestDescriptor:requestDescriptor];
    
    [[RKObjectManager sharedManager].router.routeSet addRoute:[RKRoute routeWithName:@"taskdirection" pathPattern:@"/api/v2/user/tasks/:id/:direction" method:RKRequestMethodPOST]];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/user/tasks" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    requestDescriptor = [RKRequestDescriptor requestDescriptorWithMapping:taskRequestMapping objectClass:[Task class] rootKeyPath:nil method:RKRequestMethodPOST];
    [objectManager addResponseDescriptor:responseDescriptor];
    [objectManager addRequestDescriptor:requestDescriptor];
    
    [objectManager addFetchRequestBlock:^NSFetchRequest *(NSURL *URL) {
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:@"/api/v2/user/tasks"];
        
        NSDictionary *argsDict = nil;
        BOOL match = [pathMatcher matchesPath:[URL relativePath] tokenizeQueryStrings:NO parsedArguments:&argsDict];
        if (match) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Task"];
            return fetchRequest;
        }
        
        return nil;
    }];
    
    [objectManager addFetchRequestBlock:^NSFetchRequest *(NSURL *URL) {
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:@"/api/v2/user"];
        
        NSDictionary *argsDict = nil;
        BOOL match = [pathMatcher matchesPath:[URL relativePath] tokenizeQueryStrings:NO parsedArguments:&argsDict];
        if (match) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Task"];
            return fetchRequest;
        }
        
        return nil;
    }];
    
    [objectManager addFetchRequestBlock:^NSFetchRequest *(NSURL *URL) {
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:@"/api/v2/user"];
        
        NSDictionary *argsDict = nil;
        BOOL match = [pathMatcher matchesPath:[URL relativePath] tokenizeQueryStrings:NO parsedArguments:&argsDict];
        if (match) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Reward"];
            return fetchRequest;
        }
        
        return nil;
    }];
    
    RKObjectMapping *upDownMapping = [RKObjectMapping mappingForClass:[HRPGTaskResponse class]];
    [upDownMapping addAttributeMappingsFromDictionary:@{
                                                      @"delta":              @"delta",
                                                      @"gp":            @"gold",
                                                      @"lvl":       @"level",
                                                      @"hp":            @"health",
                                                      @"mp":              @"magic",
                                                      @"exp":        @"experience",
                                                      @"_tmp.drop.key":        @"dropKey",
                                                      @"_tmp.drop.type":        @"dropType",
                                                      @"_tmp.drop.notes":        @"dropNote"}];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:upDownMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/user/tasks/:id/:direction" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    
    RKObjectMapping *loginMapping = [RKObjectMapping mappingForClass:[HRPGLoginData class]];
    [loginMapping addAttributeMappingsFromDictionary:@{
                                                        @"id":              @"id",
                                                        @"token":            @"key"}];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:loginMapping method:RKRequestMethodAny pathPattern:@"/api/v2/user/auth/local" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    RKObjectMapping *sleepMapping = [RKObjectMapping mappingForClass:[NSDictionary class]];
    [sleepMapping addAttributeMappingsFromDictionary:@{}];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:sleepMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/user/sleep" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    RKEntityMapping *entityMapping = [RKEntityMapping mappingForEntityForName:@"User" inManagedObjectStore:managedObjectStore];
    [entityMapping addAttributeMappingsFromDictionary:@{
                                                        @"_id":              @"id",
                                                        @"profile.name":            @"username",
                                                        @"preferences.dayStart" : @"dayStart",
                                                        @"preferences.sleep" : @"sleep",
                                                        @"preferences.skin" : @"skin",
                                                        @"preferences.size" : @"size",
                                                        @"preferences.shirt" : @"shirt",
                                                        @"preferences.hair.mustache" : @"hairMustache",
                                                        @"preferences.hair.bangs" : @"hairBangs",
                                                        @"preferences.hair.beard" : @"hairBeard",
                                                        @"preferences.hair.base" : @"hairBase",
                                                        @"preferences.hair.color" : @"hairColor",
                                                        @"stats.lvl":             @"level",
                                                        @"stats.gp":             @"gold",
                                                        @"stats.exp":             @"experience",
                                                        @"stats.mp":             @"magic",
                                                        @"stats.hp":             @"health",
                                                        @"stats.toNextLevel":             @"nextLevel",
                                                        @"stats.maxHealth":             @"maxHealth",
                                                        @"stats.maxMP":             @"maxMagic",
                                                        @"stats.class": @"hclass",
                                                        @"items.gear.equipped.headAccessory" : @"equippedHeadAccessory",
                                                        @"items.gear.equipped.armor" : @"equippedArmor",
                                                        @"items.gear.equipped.head" : @"equippedHead",
                                                        @"items.gear.equipped.shield" : @"equippedShield",
                                                        @"items.gear.equipped.weapon" : @"equippedWeapon",
                                                        @"items.gear.equipped.back" : @"equippedBack",
                                                        @"items.gear.costume.headAccessory" : @"costumeHeadAccessory",
                                                        @"items.gear.costume.armor" : @"costumeArmor",
                                                        @"items.gear.costume.head" : @"costumeHead",
                                                        @"items.gear.costume.shield" : @"costumeShield",
                                                        @"items.gear.costume.weapon" : @"costumeWeapon",
                                                        @"items.gear.costume.back" : @"costumeBack",
                                                        @"preferences.costume" : @"useCostume",
                                                        @"items.currentPet" : @"currentPet",
                                                        @"items.currentMount" : @"currentMount",
                                                        @"auth.timestamps.loggedin":@"lastLogin"
                                                        }];
    entityMapping.identificationAttributes = @[ @"id" ];
    entityMapping.assignsDefaultValueForMissingAttributes = YES;
    RKEntityMapping* rewardMapping = [RKEntityMapping mappingForEntityForName:@"Reward" inManagedObjectStore:managedObjectStore];
    [rewardMapping addAttributeMappingsFromDictionary:@{
                                                        @"id":          @"key",
                                                        @"text":        @"text",
                                                        @"dateCreated": @"dateCreated",
                                                        @"value":       @"value",
                                                        @"type":        @"type",
                                                        @"notes":       @"notes"
                                                        }];
    rewardMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"rewards"
                                                                                   toKeyPath:@"rewards"
                                                                                 withMapping:rewardMapping]];
    RKEntityMapping* tagMapping = [RKEntityMapping mappingForEntityForName:@"Tag" inManagedObjectStore:managedObjectStore];
    [tagMapping addAttributeMappingsFromArray:@[@"id", @"name"]];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"tags"
                                                                                  toKeyPath:@"tags"
                                                                                withMapping:tagMapping]];
    
    RKEntityMapping* gearOwnedMapping = [RKEntityMapping mappingForEntityForName:@"Gear" inManagedObjectStore:managedObjectStore];
    gearOwnedMapping.forceCollectionMapping = YES;
    [gearOwnedMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [gearOwnedMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"owned"}];
    gearOwnedMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"items.gear.owned"
                                                                                  toKeyPath:@"ownedGear"
                                                                                withMapping:gearOwnedMapping]];

    RKEntityMapping* questOwnedMapping = [RKEntityMapping mappingForEntityForName:@"Quest" inManagedObjectStore:managedObjectStore];
    questOwnedMapping.forceCollectionMapping = YES;
    [questOwnedMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [questOwnedMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"owned"}];
    questOwnedMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"items.quests"
                                                                                  toKeyPath:@"ownedQuests"
                                                                                withMapping:questOwnedMapping]];

    RKEntityMapping* foodOwnedMapping = [RKEntityMapping mappingForEntityForName:@"Food" inManagedObjectStore:managedObjectStore];
    foodOwnedMapping.forceCollectionMapping = YES;
    [foodOwnedMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [foodOwnedMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"owned"}];
    foodOwnedMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"items.food"
                                                                                  toKeyPath:@"ownedFood"
                                                                                withMapping:foodOwnedMapping]];
    
    RKEntityMapping* hPotionOwnedMapping = [RKEntityMapping mappingForEntityForName:@"HatchingPotion" inManagedObjectStore:managedObjectStore];
    hPotionOwnedMapping.forceCollectionMapping = YES;
    [hPotionOwnedMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [hPotionOwnedMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"owned"}];
    hPotionOwnedMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"items.hatchingPotions"
                                                                                  toKeyPath:@"ownedHatchingPotions"
                                                                                withMapping:hPotionOwnedMapping]];

    RKEntityMapping* eggOwnedMapping = [RKEntityMapping mappingForEntityForName:@"Egg" inManagedObjectStore:managedObjectStore];
    eggOwnedMapping.forceCollectionMapping = YES;
    [eggOwnedMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [eggOwnedMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"owned"}];
    eggOwnedMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"items.eggs"
                                                                                  toKeyPath:@"ownedEggs"
                                                                                withMapping:eggOwnedMapping]];

        responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodGET pathPattern:@"/api/v2/user" keyPath:@"habits" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodGET pathPattern:@"/api/v2/user" keyPath:@"todos" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskMapping method:RKRequestMethodGET pathPattern:@"/api/v2/user" keyPath:@"dailys" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:entityMapping method:RKRequestMethodGET pathPattern:@"/api/v2/user" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];

    
    
    RKObjectMapping *buyMapping = [RKObjectMapping mappingForClass:[HRPGUserBuyResponse class]];
    [buyMapping addAttributeMappingsFromDictionary:@{
                                                       @"stats.lvl":             @"level",
                                                       @"stats.gp":             @"gold",
                                                       @"stats.exp":             @"experience",
                                                       @"stats.mp":             @"magic",
                                                       @"stats.hp":             @"health",
                                                       @"items.gear.equipped.headAccessory" : @"equippedHeadAccessory",
                                                       @"items.gear.equipped.armor" : @"equippedArmor",
                                                       @"items.gear.equipped.head" : @"equippedHead",
                                                       @"items.gear.equipped.shield" : @"equippedShield",
                                                       @"items.gear.equipped.weapon" : @"equippedWeapon",
                                                       @"items.gear.equipped.back" : @"equippedBack",
                                                       @"items.gear.costume.headAccessory" : @"costumeHeadAccessory",
                                                       @"items.gear.costume.armor" : @"costumeArmor",
                                                       @"items.gear.costume.head" : @"costumeHead",
                                                       @"items.gear.costume.shield" : @"costumeShield",
                                                       @"items.gear.costume.weapon" : @"costumeWeapon",
                                                       @"items.gear.costume.back" : @"costumeBack",
                                                       @"items.currentPet" : @"currentPet",
                                                       @"items.currentMount" : @"currentMount",
                                                       }];
    buyMapping.assignsDefaultValueForMissingAttributes = NO;
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:buyMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/user/inventory/buy/:id" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    entityMapping = [RKEntityMapping mappingForEntityForName:@"Group" inManagedObjectStore:managedObjectStore];
    [entityMapping addAttributeMappingsFromDictionary:@{
                                                        @"_id":              @"id",
                                                        @"name":            @"name",
                                                        @"description":       @"hdescription",
                                                        @"quest.key":            @"questKey",
                                                        @"quest.progress.hp":              @"questHP",
                                                        @"quest.active":        @"questActive",
                                                        @"privacy":         @"privacy",
                                                        @"type":                @"type"
                                                        }];
    entityMapping.identificationAttributes = @[ @"id" ];
    entityMapping.assignsDefaultValueForMissingAttributes = YES;
    RKEntityMapping* chatMapping = [RKEntityMapping mappingForEntityForName:@"ChatMessage" inManagedObjectStore:managedObjectStore];
    [chatMapping addAttributeMappingsFromDictionary:@{@"id":@"id",
                                                       @"text":@"text",
                                                       @"timestamp":@"timestamp",
                                                       @"user":@"user"}];
    RKEntityMapping *chatUserMapping = [RKEntityMapping mappingForEntityForName:@"User" inManagedObjectStore:managedObjectStore];
    [chatUserMapping addAttributeMappingsFromDictionary:@{@"uuid":@"id"}];
    [chatMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:nil
                                                                                  toKeyPath:@"userObject"
                                                                                withMapping:chatUserMapping]];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"chat"
                                                                                  toKeyPath:@"chatmessages"
                                                                                withMapping:chatMapping]];
    chatMapping.identificationAttributes = @[ @"id" ];
    RKEntityMapping* collectMapping = [RKEntityMapping mappingForEntityForName:@"QuestCollect" inManagedObjectStore:managedObjectStore];
    collectMapping.forceCollectionMapping = YES;
    [collectMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [collectMapping addAttributeMappingsFromDictionary:@{@"(key)":              @"collectCount"}];
    collectMapping.identificationAttributes = @[ @"key" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"quest.progress.collect"
                                                                                  toKeyPath:@"collectStatus"
                                                                                withMapping:collectMapping]];
    RKEntityMapping* questParticipantsMapping = [RKEntityMapping mappingForEntityForName:@"User" inManagedObjectStore:managedObjectStore];
    questParticipantsMapping.forceCollectionMapping = YES;
    [questParticipantsMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"id"];
    [questParticipantsMapping addAttributeMappingsFromDictionary:@{@"(id)":              @"participateInQuest"}];
    questParticipantsMapping.identificationAttributes = @[ @"id" ];
    questParticipantsMapping.assignsDefaultValueForMissingAttributes = YES;
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"quest.members"
                                                                                  toKeyPath:@"questParticipants"
                                                                                withMapping:questParticipantsMapping]];
    
    RKEntityMapping *partyResponseMapping = [entityMapping copy];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:partyResponseMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/groups/:id/questAccept" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    
    [objectManager addResponseDescriptor:responseDescriptor];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:partyResponseMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/groups/:id/questReject" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    
    [objectManager addResponseDescriptor:responseDescriptor];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:partyResponseMapping method:RKRequestMethodPOST pathPattern:@"/api/v2/groups/:id/questAbort" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    
    [objectManager addResponseDescriptor:responseDescriptor];
    
    RKEntityMapping* memberMapping = [RKEntityMapping mappingForEntityForName:@"User" inManagedObjectStore:managedObjectStore];
    [memberMapping addAttributeMappingsFromDictionary:@{
                                                        @"_id":              @"id",
                                                        @"profile.name":            @"username",
                                                        @"preferences.dayStart" : @"dayStart",
                                                        @"preferences.sleep" : @"sleep",
                                                        @"preferences.skin" : @"skin",
                                                        @"preferences.size" : @"size",
                                                        @"preferences.shirt" : @"shirt",
                                                        @"preferences.hair.mustache" : @"hairMustache",
                                                        @"preferences.hair.bangs" : @"hairBangs",
                                                        @"preferences.hair.beard" : @"hairBeard",
                                                        @"preferences.hair.base" : @"hairBase",
                                                        @"preferences.hair.color" : @"hairColor",
                                                        @"stats.lvl":             @"level",
                                                        @"stats.gp":             @"gold",
                                                        @"stats.exp":             @"experience",
                                                        @"stats.mp":             @"magic",
                                                        @"stats.hp":             @"health",
                                                        @"stats.toNextLevel":             @"nextLevel",
                                                        @"stats.maxHealth":             @"maxHealth",
                                                        @"stats.maxMP":             @"maxMagic",
                                                        @"stats.class": @"hclass",
                                                        @"items.gear.equipped.headAccessory" : @"equippedHeadAccessory",
                                                        @"items.gear.equipped.armor" : @"equippedArmor",
                                                        @"items.gear.equipped.head" : @"equippedHead",
                                                        @"items.gear.equipped.shield" : @"equippedShield",
                                                        @"items.gear.equipped.weapon" : @"equippedWeapon",
                                                        @"items.gear.equipped.back" : @"equippedBack",
                                                        @"items.currentPet" : @"currentPet",
                                                        @"items.currentMount" : @"currentMount",
                                                        @"auth.timestamps.loggedin":@"lastLogin"
                                                        }];
    memberMapping.identificationAttributes = @[ @"id" ];
    [entityMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"members"
                                                                                  toKeyPath:@"member"
                                                                                withMapping:memberMapping]];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:entityMapping method:RKRequestMethodGET pathPattern:@"/api/v2/groups/:id" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:entityMapping method:RKRequestMethodGET pathPattern:@"/api/v2/groups" keyPath:nil statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    
    [objectManager addResponseDescriptor:responseDescriptor];
    
    RKEntityMapping *gearMapping = [RKEntityMapping mappingForEntityForName:@"Gear" inManagedObjectStore:managedObjectStore];
    gearMapping.forceCollectionMapping = YES;
    [gearMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [gearMapping addAttributeMappingsFromDictionary:@{
                                                        @"(key).text":              @"text",
                                                        @"(key).notes":            @"notes",
                                                        @"(key).con":       @"con",
                                                        @"(key).value":            @"value",
                                                        @"(key).type":              @"type",
                                                        @"(key).klass":        @"klass",
                                                        @"(key).index":        @"index",
                                                        @"(key).str":        @"str",
                                                        @"(key).int":        @"intelligence",
                                                        @"(key).per":        @"per"}];
    gearMapping.identificationAttributes = @[ @"key" ];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:gearMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"gear.flat" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];

    RKEntityMapping *eggMapping = [RKEntityMapping mappingForEntityForName:@"Egg" inManagedObjectStore:managedObjectStore];
    eggMapping.forceCollectionMapping = YES;
    [eggMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [eggMapping addAttributeMappingsFromDictionary:@{
                                                      @"(key).text":              @"text",
                                                      @"(key).adjective":            @"adjective",
                                                      @"(key).canBuy":       @"canBuy",
                                                      @"(key).value":            @"value",
                                                      @"(key).notes":              @"notes",
                                                      @"(key).mountText":        @"mountText",
                                                      @"(key).dialog":        @"dialog",
                                                      @"@metadata.mapping.rootKeyPath":        @"type"}];
    eggMapping.identificationAttributes = @[ @"key" ];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:eggMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"eggs" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    RKEntityMapping *hatchingPotionMapping = [RKEntityMapping mappingForEntityForName:@"HatchingPotion" inManagedObjectStore:managedObjectStore];
    hatchingPotionMapping.forceCollectionMapping = YES;
    [hatchingPotionMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [hatchingPotionMapping addAttributeMappingsFromDictionary:@{
                                                     @"(key).text":              @"text",
                                                     @"(key).value":            @"value",
                                                     @"(key).notes":              @"notes",
                                                     @"(key).dialog":        @"dialog",
                                                     @"@metadata.mapping.rootKeyPath":        @"type"}];
    hatchingPotionMapping.identificationAttributes = @[ @"key" ];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:hatchingPotionMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"hatchingPotions" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    RKEntityMapping *foodMapping = [RKEntityMapping mappingForEntityForName:@"Food" inManagedObjectStore:managedObjectStore];
    foodMapping.forceCollectionMapping = YES;
    [foodMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [foodMapping addAttributeMappingsFromDictionary:@{
                                                     @"(key).text":              @"text",
                                                     @"(key).target":            @"target",
                                                     @"(key).canBuy":       @"canBuy",
                                                     @"(key).value":            @"value",
                                                     @"(key).notes":              @"notes",
                                                     @"(key).article":        @"article",
                                                     @"(key).dialog":        @"dialog",
                                                     @"@metadata.mapping.rootKeyPath":        @"type"}];
    foodMapping.identificationAttributes = @[ @"key" ];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:foodMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"food" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    RKEntityMapping *spellMapping = [RKEntityMapping mappingForEntityForName:@"Spell" inManagedObjectStore:managedObjectStore];
    spellMapping.forceCollectionMapping = YES;
    [spellMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [spellMapping addAttributeMappingsFromDictionary:@{
                                                       @"(key).text":              @"text",
                                                       @"(key).lvl":            @"level",
                                                       @"(key).notes":              @"notes",
                                                       @"@metadata.mapping.rootKeyPath":        @"klass"}];
    spellMapping.identificationAttributes = @[ @"key" ];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:spellMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"spells.healer" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:spellMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"spells.wizard" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:spellMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"spells.warrior" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:spellMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"spells.rogue" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    
    RKEntityMapping *potionMapping = [RKEntityMapping mappingForEntityForName:@"Potion" inManagedObjectStore:managedObjectStore];
    [potionMapping addAttributeMappingsFromDictionary:@{
                                                        @"text":              @"text",
                                                        @"key":            @"key",
                                                        @"value":       @"value",
                                                        @"notes":              @"notes",
                                                        @"type":              @"type",}];
    potionMapping.identificationAttributes = @[ @"key" ];
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:potionMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"potion" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];
    RKEntityMapping *questMapping = [RKEntityMapping mappingForEntityForName:@"Quest" inManagedObjectStore:managedObjectStore];
    questMapping.forceCollectionMapping = YES; 
    [questMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    RKEntityMapping* questCollectMapping = [RKEntityMapping mappingForEntityForName:@"QuestCollect" inManagedObjectStore:managedObjectStore];
    questCollectMapping.forceCollectionMapping = YES;
    [questCollectMapping addAttributeMappingFromKeyOfRepresentationToAttribute:@"key"];
    [questCollectMapping addAttributeMappingsFromDictionary:@{
                                                              @"(key).text":              @"text",
                                                              @"(key).count":            @"count"}];
    questCollectMapping.identificationAttributes = @[ @"key" ];
    [questMapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"(key).collect"
                                                                                 toKeyPath:@"collect"
                                                                               withMapping:questCollectMapping]];
    [questMapping addAttributeMappingsFromDictionary:@{
                                                     @"(key).text":              @"text",
                                                     @"(key).completition":            @"completition",
                                                     @"(key).canBuy":       @"canBuy",
                                                     @"(key).value":            @"value",
                                                     @"(key).notes":              @"notes",
                                                     @"(key).drop.gp":        @"dropGp",
                                                     @"(key).drop.exp":        @"dropExp",
                                                     @"(key).boss.name":        @"bossName",
                                                     @"(key).boss.hp":        @"bossHp",
                                                     @"(key).boss.str":        @"bossStr",
                                                     @"@metadata.mapping.rootKeyPath":        @"type"}];
    questMapping.identificationAttributes = @[ @"key" ];
    
    responseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:questMapping method:RKRequestMethodGET pathPattern:@"/api/v2/content" keyPath:@"quests" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:responseDescriptor];

    [self setCredentials];
    defaults = [NSUserDefaults standardUserDefaults];
    if (currentUser != nil) {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id==%@", currentUser];
        [fetchRequest setPredicate:predicate];
        NSArray *fetchedObjects = [[self getManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
        if ([fetchedObjects count] > 0) {
            user = fetchedObjects[0];
        } else {
            [self fetchUser:^() {
                
            }onError:^() {
                
            }];
        }
    }
    
    if (iconFactory == nil) {
        iconFactory = [NIKFontAwesomeIconFactory tabBarItemIconFactory];
        iconFactory.colors = @[[UIColor whiteColor]];
        iconFactory.size = 35;
    }
}

- (void) resetSavedDatabase {
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSManagedObjectContext *lmanagedObjectContext = [RKManagedObjectStore defaultStore].persistentStoreManagedObjectContext;
        [lmanagedObjectContext performBlockAndWait:^{
            NSError *error = nil;
            for (NSEntityDescription *entity in [RKManagedObjectStore defaultStore].managedObjectModel) {
                NSFetchRequest *fetchRequest = [NSFetchRequest new];
                [fetchRequest setEntity:entity];
                [fetchRequest setIncludesSubentities:NO];
                NSArray *objects = [lmanagedObjectContext executeFetchRequest:fetchRequest error:&error];
                if (! objects) RKLogWarning(@"Failed execution of fetch request %@: %@", fetchRequest, error);
                for (NSManagedObject *managedObject in objects) {
                    [lmanagedObjectContext deleteObject:managedObject];
                }
            }
            
            BOOL success = [lmanagedObjectContext save:&error];
            if (!success) RKLogWarning(@"Failed saving managed object context: %@", error);
        }];
    }];
    [operation setCompletionBlock:^{
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [self fetchContent:^() {
            
        }onError:^() {
            
        }];    }];
    [operation start];
}

- (NSManagedObjectContext *)getManagedObjectContext {
    return [managedObjectStore mainQueueManagedObjectContext];
}

- (void) setCredentials {
    
    PDKeychainBindings *keyChain = [PDKeychainBindings sharedKeychainBindings];
    currentUser = [keyChain stringForKey:@"id"];
    [[RKObjectManager sharedManager].HTTPClient setDefaultHeader:@"x-api-user" value:currentUser];
    [[RKObjectManager sharedManager].HTTPClient setDefaultHeader:@"x-api-key" value:[keyChain stringForKey:@"key"]];
}

-(UIColor*) getColorForValue:(NSNumber *)value {
    NSInteger intValue = [value integerValue];
    if (intValue < -20) {
        return [UIColor colorWithRed:0.824 green:0.113 blue:0.104 alpha:1.000];
    } else if (intValue < -10) {
        return [UIColor colorWithRed:0.906 green:0.328 blue:0.113 alpha:1.000];
    } else if (intValue < -1) {
        return [UIColor colorWithRed:0.966 green:0.517 blue:0.117 alpha:1.000];
    } else if (intValue < 1) {
        return [UIColor colorWithRed:0.847 green:0.597 blue:0.077 alpha:1.000];
    } else if (intValue < 5) {
        return [UIColor colorWithRed:0.251 green:0.662 blue:0.127 alpha:1.000];
    } else if (intValue < 10) {
        return [UIColor colorWithRed:0.124 green:0.627 blue:0.755 alpha:1.000];
    } else {
        return [UIColor colorWithRed:0.231 green:0.442 blue:0.964 alpha:1.000];
    }
}

- (void) fetchContent:(void (^)())successBlock onError:(void (^)())errorBlock{
    [[RKObjectManager sharedManager] getObjectsAtPath:@"/api/v2/content" parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        [defaults setObject:[NSDate date] forKey:@"lastContentFetch"];
        [defaults synchronize];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        errorBlock();
        return;
    }];
}

- (void) fetchTasks:(void (^)())successBlock onError:(void (^)())errorBlock{
    [[RKObjectManager sharedManager] getObjectsAtPath:@"/api/v2/user/tasks" parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        [defaults setObject:[NSDate date] forKey:@"lastTaskFetch"];
        [defaults synchronize];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        errorBlock();
        return;
    }];
}

- (void) fetchUser:(void (^)())successBlock onError:(void (^)())errorBlock{
    [[RKObjectManager sharedManager] getObjectsAtPath:@"/api/v2/user" parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        //user = (User*)[mappingResult dictionary][[NSNull null]];
        if (![currentUser isEqualToString:user.id]) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"User"];
            [fetchRequest setReturnsObjectsAsFaults:NO];
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id==%@", currentUser];
            [fetchRequest setPredicate:predicate];
            NSError *error;
            NSArray *fetchedObjects = [[self getManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
            if ([fetchedObjects count] > 0) {
                user = fetchedObjects[0];
            }
        }
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        [defaults setObject:[NSDate date] forKey:@"lastTaskFetch"];
        [defaults synchronize];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];

}

- (void) fetchGroup:(NSString*)groupID onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock{
    [[RKObjectManager sharedManager] getObjectsAtPath:[NSString stringWithFormat:@"/api/v2/groups/%@", groupID] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

- (void) fetchGroups:(NSString*)groupType onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock{
    NSDictionary *params = @{@"type": groupType};
    [[RKObjectManager sharedManager] getObjectsAtPath:@"/api/v2/groups" parameters:params success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        if ([groupType isEqualToString:@"party"]) {
            Group *party = (Group*)[mappingResult firstObject];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:party.id forKey:@"partyID"];
            [defaults synchronize];
        }
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) upDownTask:(Task*)task direction:(NSString*)withDirection onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:nil path:[NSString stringWithFormat:@"/api/v2/user/tasks/%@/%@", task.id, withDirection] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        HRPGTaskResponse *taskResponse = (HRPGTaskResponse*)[mappingResult firstObject];
        task.value = [NSNumber numberWithFloat:[task.value floatValue] + [taskResponse.delta floatValue]];
        if ([user.level integerValue] < [taskResponse.level integerValue]) {
            [self displayLevelUpNotification];
            //Set experience to the amount, that was missing for the next level. So that the notification
            //displays the correct amount of experience gained
            user.experience = [NSNumber numberWithFloat:[user.experience floatValue] - [user.nextLevel floatValue]];
        }
        user.level = taskResponse.level;
        NSNumber *expDiff = [NSNumber numberWithFloat: [taskResponse.experience floatValue] - [user.experience floatValue]];
        user.experience = taskResponse.experience;
        NSNumber *healthDiff = [NSNumber numberWithFloat: [taskResponse.health floatValue] - [user.health floatValue]];
        user.health = taskResponse.health;
        user.magic = taskResponse.magic;
        
        NSNumber *goldDiff = [NSNumber numberWithFloat: [taskResponse.gold floatValue] - [user.gold floatValue]];
        user.gold = taskResponse.gold;
        [self displayTaskSuccessNotification:healthDiff withExperienceDiff:expDiff withGoldDiff:goldDiff];
        if ([task.type  isEqual: @"daily"] || [task.type  isEqual: @"todo"]) {
            task.completed = [NSNumber numberWithBool:([withDirection  isEqual: @"up"])];
        }
        if (taskResponse.dropKey) {
            NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
            // Edit the entity name as appropriate.
            NSEntityDescription *entity = [NSEntityDescription entityForName:@"Item" inManagedObjectContext:[self getManagedObjectContext]];
            [fetchRequest setEntity:entity];
            NSPredicate *predicate;
            predicate = [NSPredicate predicateWithFormat:@"type==%@ || key==%@", taskResponse.dropType, taskResponse.dropKey];
            [fetchRequest setPredicate:predicate];
            NSError * error = nil;
            NSArray *fetchedObjects = [[self getManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
            if([fetchedObjects count] == 1) {
                Item *droppedItem = [fetchedObjects objectAtIndex:0];
                droppedItem.owned = [NSNumber numberWithLong:([droppedItem.owned integerValue] + 1) ];
                [self displayDropNotification:taskResponse.dropKey withType:taskResponse.dropType withNote:taskResponse.dropNote];
            }
        }
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) getReward:(NSString*)rewardID onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:nil path:[NSString stringWithFormat:@"/api/v2/user/tasks/%@/down", rewardID] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        HRPGTaskResponse *taskResponse = (HRPGTaskResponse*)[mappingResult firstObject];
        if ([user.level integerValue] < [taskResponse.level integerValue]) {
            [self displayLevelUpNotification];
            //Set experience to the amount, that was missing for the next level. So that the notification
            //displays the correct amount of experience gained
            user.experience = [NSNumber numberWithFloat:[user.experience floatValue] - [user.nextLevel floatValue]];
        }
        user.level = taskResponse.level;
        NSNumber *expDiff = [NSNumber numberWithFloat: [taskResponse.experience floatValue] - [user.experience floatValue]];
        user.experience = taskResponse.experience;
        NSNumber *healthDiff = [NSNumber numberWithFloat: [taskResponse.health floatValue] - [user.health floatValue]];
        user.health = taskResponse.health;
        user.magic = taskResponse.magic;
        
        NSNumber *goldDiff = [NSNumber numberWithFloat: [taskResponse.gold floatValue] - [user.gold floatValue]];
        user.gold = taskResponse.gold;
        [self displayTaskSuccessNotification:healthDiff withExperienceDiff:expDiff withGoldDiff:goldDiff];
        if (taskResponse.dropKey) {
            NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
            // Edit the entity name as appropriate.
            NSEntityDescription *entity = [NSEntityDescription entityForName:@"Item" inManagedObjectContext:[self getManagedObjectContext]];
            [fetchRequest setEntity:entity];
            NSPredicate *predicate;
            predicate = [NSPredicate predicateWithFormat:@"type==%@ || key==%@", taskResponse.dropType, taskResponse.dropKey];
            [fetchRequest setPredicate:predicate];
            NSError * error = nil;
            NSArray *fetchedObjects = [[self getManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
            if([fetchedObjects count] == 1) {
                Item *droppedItem = [fetchedObjects objectAtIndex:0];
                droppedItem.owned = [NSNumber numberWithLong:([droppedItem.owned integerValue] + 1) ];
                [self displayDropNotification:taskResponse.dropKey withType:taskResponse.dropType withNote:taskResponse.dropNote];
            }
        }
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}


-(void) createTask:(Task*)task onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:task path:nil parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        errorBlock();
        return;
    }];
}

-(void) updateTask:(Task*)task onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] putObject:task path:nil parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) deleteTask:(Task*)task onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] deleteObject:task path:nil parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}


-(void) loginUser:(NSString *)username withPassword:(NSString *)password onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    NSDictionary *params = @{@"username": username, @"password": password};
    [[RKObjectManager sharedManager] postObject:Nil path:@"/api/v2/user/auth/local" parameters:params success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        HRPGLoginData *loginData = (HRPGLoginData*)[mappingResult firstObject];
        PDKeychainBindings *keyChain = [PDKeychainBindings sharedKeychainBindings];
        [keyChain setString:loginData.id forKey:@"id"];
        [keyChain setString:loginData.key forKey:@"key"];
        
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];

}

-(void) sleepInn:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:Nil path:@"/api/v2/user/sleep" parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        user.sleep = !user.sleep;
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
    
}

-(void) buyObject:(MetaReward*)reward onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:Nil path:[NSString stringWithFormat:@"/api/v2/user/inventory/buy/%@", reward.key] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        HRPGUserBuyResponse *response = [mappingResult firstObject];
        user.health = response.health;
        user.gold = response.gold;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) acceptQuest:(NSString*)group withQuest:(NSString*)questID useForce:(Boolean)force onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    NSDictionary *params = nil;

    //if (force) {
    //    params = @{@"force": force};
    //}
    if (questID) {
        params = @{@"key": questID};
    }
    [[RKObjectManager sharedManager] postObject:nil path:[NSString stringWithFormat:@"/api/v2/groups/%@/questAccept", group] parameters:params success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) rejectQuest:(NSString*)group onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:nil path:[NSString stringWithFormat:@"/api/v2/groups/%@/questReject", group] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

-(void) abortQuest:(NSString*)group onSuccess:(void (^)())successBlock onError:(void (^)())errorBlock {
    [[RKObjectManager sharedManager] postObject:nil path:[NSString stringWithFormat:@"/api/v2/groups/%@/questAbort", group] parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSError *executeError = nil;
        [[self getManagedObjectContext] saveToPersistentStore:&executeError];
        successBlock();
        return;
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 503) {
            [self displayServerError];
        } else {
            [self displayNetworkError];
        }
        errorBlock();
        return;
    }];
}

- (void) displayNetworkError {
    NSDictionary *options = @{kCRToastTextKey : NSLocalizedString(@"Network error", nil),
                              kCRToastSubtitleTextKey :NSLocalizedString(@"Couldn't connect to the server. Check your network connection", nil),
                              kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastSubtitleTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastBackgroundColorKey : [UIColor colorWithRed:1.0f green:0.22f blue:0.22f alpha:1.0f],
                              kCRToastImageKey : [iconFactory createImageForIcon:NIKFontAwesomeIconExclamationCircle]
                              };
    [CRToastManager showNotificationWithOptions:options
                                completionBlock:^{
                                }];
}

- (void) displayServerError {
    NSDictionary *options = @{kCRToastTextKey : NSLocalizedString(@"Server error", nil),
                              kCRToastSubtitleTextKey :NSLocalizedString(@"There seems to be a problem with the server. Try again later", nil),
                              kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastSubtitleTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastBackgroundColorKey : [UIColor colorWithRed:1.0f green:0.22f blue:0.22f alpha:1.0f],
                              kCRToastImageKey : [iconFactory createImageForIcon:NIKFontAwesomeIconExclamationCircle]
                              };
    [CRToastManager showNotificationWithOptions:options
                                completionBlock:^{
                                }];
}

-(void) displayTaskSuccessNotification:(NSNumber*) healthDiff withExperienceDiff:(NSNumber*)expDiff withGoldDiff:(NSNumber*)goldDiff {
    UIColor *notificationColor = [UIColor colorWithRed:0.768 green:0.782 blue:0.105 alpha:1.000];
    NSString *content;
    if ([healthDiff intValue] < 0) {
        notificationColor = [UIColor colorWithRed:1.0f green:0.22f blue:0.22f alpha:1.0f];
        content = [NSString stringWithFormat:@"Health: %.1f", [healthDiff floatValue]];
    } else {
        content = [NSString stringWithFormat:@"Experience: %ld\nGold: %.2f", (long)[expDiff integerValue], [goldDiff floatValue]];
    }
    NSDictionary *options = @{kCRToastTextKey : content,
                              kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastBackgroundColorKey : notificationColor,
                              kCRToastImageKey : [iconFactory createImageForIcon:NIKFontAwesomeIconCheck]
                              };
    [CRToastManager showNotificationWithOptions:options
                                completionBlock:^{
                                }];
}

-(void) displayLevelUpNotification {
    UIColor *notificationColor = [UIColor colorWithRed:0.251 green:0.662 blue:0.127 alpha:1.000];
    NSDictionary *options = @{kCRToastTextKey : NSLocalizedString(@"Level up!", nil),
                              kCRToastSubtitleTextKey : [NSString stringWithFormat:@"Level %ld", ([user.level integerValue]+1)],
                              kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastSubtitleTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastBackgroundColorKey : notificationColor,
                              kCRToastImageKey : [iconFactory createImageForIcon:NIKFontAwesomeIconArrowUp]
                              };
    [CRToastManager showNotificationWithOptions:options
                                completionBlock:^{
                                }];
}

-(void) displayDropNotification:(NSString*)name withType:(NSString*)type withNote:(NSString*)note {
    UIColor *notificationColor = [UIColor colorWithRed:0.231 green:0.442 blue:0.964 alpha:1.000];
    NSDictionary *options = @{kCRToastTextKey : [NSString stringWithFormat:NSLocalizedString(@"You found a %@ %@", nil), name, type],
                              kCRToastSubtitleTextKey : note,
                              kCRToastTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastSubtitleTextAlignmentKey : @(NSTextAlignmentLeft),
                              kCRToastBackgroundColorKey : notificationColor,
                              kCRToastImageKey : [iconFactory createImageForIcon:NIKFontAwesomeIconCheck]
                              };
    [CRToastManager showNotificationWithOptions:options
                                completionBlock:^{
                                }];
}

- (User*) getUser {
    return user;
}

- (void) getImage:(NSString*) imageName onSuccess:(void (^)(UIImage* image))successBlock {
    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    [manager downloadWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://pherth.net/habitrpg/%@.png", imageName]]
                     options:0
                    progress:^(NSInteger receivedSize, NSInteger expectedSize)
     {
     }
                   completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished)
     {
         if (image)
         {
             successBlock(image);
         } else {
             NSLog(@"%@: %@", imageName, error);
         }
     }];
}

- (UIImage*)getCachedImage:(NSString *)imageName {
    UIImage *image = [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:imageName];
    if (image)
    {
        return image;
    } else {
        return nil;
    }
}

- (void)setCachedImage:(UIImage *)image withName:(NSString *)imageName onSuccess:(void (^)())successBlock {
    [[SDImageCache sharedImageCache] storeImage:image forKey:imageName];
}

@end

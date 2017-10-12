//
//  MPKitTune.m
//
//  Copyright 2016 mParticle, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "MPKitTune.h"
#import <UIKit/UIKit.h>

NSString * const tnAdvertiserId = @"advertiserId";
NSString * const tnConversionKey = @"conversionKey";
NSString * const tnOverridePackageName = @"overridePackageName";

NSString * const MPKitTuneErrorDomain = @"com.mparticle.kits.tune";
NSString * const MPKitTuneErrorMessageKey = @"mParticle-Tune Error";

@interface MPKitTune ()
@property (nonatomic) NSString *platform;
@property (nonatomic) NSString *advertiserId;
@property (nonatomic) NSString *conversionKey;
@property (nonatomic) NSString *identifierForAdvertiser;
@property (nonatomic) NSString *packageName;
@property (nonatomic) NSString *sdkVersion;
@property (nonatomic) NSString *adTrackingEnabled;
@property (nonatomic) NSString *userAgent;
@end


@implementation MPKitTune

@synthesize kitApi = _kitApi;

+ (NSNumber *)kitCode {
    return @32;
}

+ (void)load {
    MPKitRegister *kitRegister = [[MPKitRegister alloc] initWithName:@"Tune" className:@"MPKitTune"];
    [MParticle registerExtension:kitRegister];
}

+ (NSString *)advertiserId {
    NSString *advertiserId = nil;
    Class MPIdentifierManager = NSClassFromString(@"ASIdentifierManager");
    if (MPIdentifierManager) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL selector = NSSelectorFromString(@"sharedManager");
        id<NSObject> adIdentityManager = [MPIdentifierManager performSelector:selector];

        selector = NSSelectorFromString(@"advertisingIdentifier");
        advertiserId = [[adIdentityManager performSelector:selector] UUIDString];
#pragma clang diagnostic pop
#pragma clang diagnostic pop
    }

    return advertiserId;
}

- (MPKitExecStatus *)didFinishLaunchingWithConfiguration:(NSDictionary *)configuration {
    MPKitExecStatus *execStatus = nil;

    _configuration = configuration;
    _advertiserId = configuration[tnAdvertiserId];
    _conversionKey = configuration[tnConversionKey];
    BOOL validConfiguration = _advertiserId != nil && _conversionKey != nil;
    if (!validConfiguration) {
        execStatus = [[MPKitExecStatus alloc] initWithSDKCode:[[self class] kitCode] returnCode:MPKitReturnCodeRequirementsNotMet];
        return execStatus;
    }

    _platform = @"ios";
    _identifierForAdvertiser = [self advertiserId];
    NSDictionary *bundleInfoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *bundleIdentifier = bundleInfoDictionary[@"CFBundleIdentifier"];
    NSString *overridePackageName = configuration[tnOverridePackageName];
    _packageName = overridePackageName && ![overridePackageName isEqualToString:@""] ? overridePackageName : bundleIdentifier;
    _sdkVersion = [UIDevice currentDevice].systemVersion;
    _adTrackingEnabled = _identifierForAdvertiser ? [@YES stringValue] : [@NO stringValue];

    _started = YES;
    
    [self checkForAttribution];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = @{mParticleKitInstanceKey:[[self class] kitCode]};

        [[NSNotificationCenter defaultCenter] postNotificationName:mParticleKitDidBecomeActiveNotification
                                                            object:nil
                                                          userInfo:userInfo];
    });

    execStatus = [[MPKitExecStatus alloc] initWithSDKCode:[[self class] kitCode] returnCode:MPKitReturnCodeSuccess];
    return execStatus;
}

static NSString* const USER_DEFAULT_KEY_PREFIX = @"_TUNE_";

+ (id)userDefaultValueForKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *newKey = [NSString stringWithFormat:@"%@%@", USER_DEFAULT_KEY_PREFIX, key];

    id value = [defaults valueForKey:newKey];

    // return value for new key if exists, else return value for old key
    if( value ) return value;
    return [defaults valueForKey:key];
}

+ (void)setUserDefaultValue:(id)value forKey:(NSString* )key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    key = [NSString stringWithFormat:@"%@%@", USER_DEFAULT_KEY_PREFIX, key];
    [defaults setValue:value forKey:key];
    [defaults synchronize];
}

- (NSError *)errorWithMessage:(NSString *)message {
    NSError *error = [NSError errorWithDomain:MPKitTuneErrorDomain code:0 userInfo:@{MPKitTuneErrorMessageKey: message}];
    return error;
}

- (void)checkForAttribution {
    NSString * const TUNE_KEY_DEEPLINK_CHECKED = @"mat_deeplink_checked";

    if (!_advertiserId
        || !_identifierForAdvertiser
        || [[self class] userDefaultValueForKey:TUNE_KEY_DEEPLINK_CHECKED]) {
        NSError *error = [self errorWithMessage:@"Requirements not met"];
        [_kitApi onAttributionCompleteWithResult:nil error:error];
        return;
    }

    // persist state so deeplink isn't requested twice
    [[self class] setUserDefaultValue:@YES forKey:TUNE_KEY_DEEPLINK_CHECKED];

    __weak MPKitTune *weakSelf = self;
    dispatch_block_t getUserAgent = ^{
        UIWebView *webView = [[UIWebView alloc] initWithFrame:CGRectZero];
        __strong MPKitTune *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_userAgent = [NSString stringWithFormat:@"%@", [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"]];
    };

    if ([NSThread isMainThread]) {
        getUserAgent();
    } else {
        dispatch_sync(dispatch_get_main_queue(), getUserAgent);
    }

    NSString * const TUNE_KEY_PLATFORM = @"platform";
    NSString * const TUNE_KEY_ADVERTISER_ID = @"advertiser_id";
    NSString * const TUNE_KEY_CONVERSION_USER_AGENT = @"conversion_user_agent";
    NSString * const TUNE_KEY_HTTPS = @"https";
    NSString * const TUNE_KEY_IOS_AD_TRACKING = @"ios_ad_tracking";
    NSString * const TUNE_KEY_IOS_IFA_DEEPLINK = @"ad_id";
    NSString * const TUNE_KEY_PACKAGE_NAME = @"package_name";
    NSString * const TUNE_KEY_VER = @"ver";
    NSString * const TUNE_SERVER_DOMAIN_DEEPLINK = @"deeplink.mobileapptracking.com";
    NSString * const TUNE_SERVER_PATH_DEEPLINK = @"v1/link.txt";

    NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@://%@.%@/%@",
                                  TUNE_KEY_HTTPS,
                                  _advertiserId,
                                  TUNE_SERVER_DOMAIN_DEEPLINK,
                                  TUNE_SERVER_PATH_DEEPLINK];
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSMutableArray *queryItems = [NSMutableArray array];
    NSURLQueryItem *platform = [NSURLQueryItem queryItemWithName:TUNE_KEY_PLATFORM value:_platform];
    NSURLQueryItem *advertiserId = [NSURLQueryItem queryItemWithName:TUNE_KEY_ADVERTISER_ID value:_advertiserId];
    NSURLQueryItem *version = [NSURLQueryItem queryItemWithName:TUNE_KEY_VER value:_sdkVersion];
    NSURLQueryItem *packageName = [NSURLQueryItem queryItemWithName:TUNE_KEY_PACKAGE_NAME value:_packageName];
    NSURLQueryItem *identifierForAdvertiser = [NSURLQueryItem queryItemWithName:TUNE_KEY_IOS_IFA_DEEPLINK value:_identifierForAdvertiser];
    NSURLQueryItem *adTrackingEnabled = [NSURLQueryItem queryItemWithName:TUNE_KEY_IOS_AD_TRACKING value:_adTrackingEnabled];
    NSURLQueryItem *userAgent = [NSURLQueryItem queryItemWithName:TUNE_KEY_CONVERSION_USER_AGENT value:_userAgent];
    [queryItems addObject:platform];
    [queryItems addObject:advertiserId];
    [queryItems addObject:version];
    [queryItems addObject:packageName];
    [queryItems addObject:identifierForAdvertiser];
    [queryItems addObject:adTrackingEnabled];
    [queryItems addObject:userAgent];

    components.queryItems = queryItems;
    NSURL *url = components.URL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request addValue:_conversionKey forHTTPHeaderField:@"X-MAT-Key"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        BOOL success = NO;
        if (!error) {
            NSString *link = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if(200 == (int)[(NSHTTPURLResponse*)response statusCode]) {
                __block NSURL *deepLink = [NSURL URLWithString:link];
                if (deepLink) {
                    NSDictionary *info = @{@"deepLink": deepLink};
                    success = YES;

                    MPAttributionResult *attributionResult = [[MPAttributionResult alloc] init];
                    attributionResult.linkInfo = info;

                    [_kitApi onAttributionCompleteWithResult:attributionResult error:nil];
                } else {
                    NSError *attributionError = [self errorWithMessage:[NSString stringWithFormat:@"Unable to create NSURL with string: %@", link]];
                    [_kitApi onAttributionCompleteWithResult:nil error:attributionError];
                }
            } else {
                NSError *attributionError = [self errorWithMessage:[NSString stringWithFormat:@"Received non-200 response code: %d", (int)[(NSHTTPURLResponse *)response statusCode]]];
                [_kitApi onAttributionCompleteWithResult:nil error:attributionError];
            }
        }
        else {
            NSError *attributionError = [self errorWithMessage:[NSString stringWithFormat:@"HTTP request failed with error: %@", error]];
            [_kitApi onAttributionCompleteWithResult:nil error:attributionError];
        }
    }] resume];
}

- (MPKitExecStatus *)continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray * _Nullable))restorationHandler {
    MPKitExecStatus *execStatus = nil;
    
    [self checkForAttribution];
    
    execStatus = [[MPKitExecStatus alloc] initWithSDKCode:[[self class] kitCode] returnCode:MPKitReturnCodeSuccess];
    return execStatus;
}

- (MPKitExecStatus *)openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options {
    MPKitExecStatus *execStatus = nil;
    
    [self checkForAttribution];
    
    execStatus = [[MPKitExecStatus alloc] initWithSDKCode:[[self class] kitCode] returnCode:MPKitReturnCodeSuccess];
    return execStatus;
}

- (MPKitExecStatus *)openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    MPKitExecStatus *execStatus = nil;
    
    [self checkForAttribution];
    
    execStatus = [[MPKitExecStatus alloc] initWithSDKCode:[[self class] kitCode] returnCode:MPKitReturnCodeSuccess];
    return execStatus;
}

@end

// Copyright 2017, the Flutter project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#import "GoogleSignInPlugin.h"

@interface NSError(FlutterError)
@property (readonly, nonatomic) FlutterError *flutterError;
@end

@implementation NSError(FlutterError)
- (FlutterError *)flutterError {
  return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", self.code]
                             message:self.domain
                             details:self.localizedDescription];
}
@end

@implementation GoogleSignInPlugin {
  NSMutableArray<FlutterResultReceiver>* _accountRequests;
}

- (instancetype)initWithFlutterView:(FlutterViewController *)flutterView {
  self = [super init];
  if (self) {
    FlutterMethodChannel *channel = [FlutterMethodChannel
        methodChannelWithName:@"plugins.flutter.io/google_sign_in"
              binaryMessenger:flutterView];
    _accountRequests = [[NSMutableArray alloc] init];
    [GIDSignIn sharedInstance].delegate = self;
    [GIDSignIn sharedInstance].uiDelegate = flutterView;
    [channel setMethodCallHandler:^(FlutterMethodCall *call,
                                    FlutterResultReceiver result) {
      [self handleMethodCall:call result:result];
    }];
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResultReceiver)result {
    if ([call.method isEqualToString:@"init"]) {
        NSError *error;
        [[GGLContext sharedInstance] configureWithError:&error];
        [GIDSignIn sharedInstance].scopes = call.arguments[@"scopes"];
        [GIDSignIn sharedInstance].hostedDomain = call.arguments[@"hostedDomain"];
        result(error.flutterError);
    } else if ([call.method isEqualToString:@"signInSilently"]) {
        [_accountRequests insertObject:result atIndex:0];
        [[GIDSignIn sharedInstance] signInSilently];
    } else if ([call.method isEqualToString:@"signIn"]) {
        [_accountRequests insertObject:result atIndex:0];
        [[GIDSignIn sharedInstance] signIn];
    } else if ([call.method isEqualToString:@"getToken"]) {
        GIDGoogleUser *currentUser = [GIDSignIn sharedInstance].currentUser;
        GIDAuthentication *auth = currentUser.authentication;
        [auth getTokensWithHandler:^void(GIDAuthentication* authentication,
                                         NSError* error) {
          result(error != nil ? error.flutterError : authentication.accessToken);
        }];
    } else if ([call.method isEqualToString:@"signOut"]) {
        [[GIDSignIn sharedInstance] signOut];
        [self respondWithAccount:nil error:nil];
    } else if ([call.method isEqualToString:@"disconnect"]) {
        [_accountRequests insertObject:result atIndex:0];
        [[GIDSignIn sharedInstance] disconnect];
    } else {
        [NSException
         raise:@"Unexpected argument"
         format:@"FlutterGoogleSignIn received an unexpected method call"];
    }
}

- (BOOL)handleURL:(NSURL *)url
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation {
  return [[GIDSignIn sharedInstance] handleURL:url
                             sourceApplication:sourceApplication
                                    annotation:annotation];
}

- (void)signIn:(GIDSignIn*)signIn
didSignInForUser:(GIDGoogleUser*)user
     withError:(NSError*)error {
  NSDictionary* response;
  if (error != nil) {
    if (error.code == -4) {
      // Occurs when silent sign-in is not possible, return an empty user in this case
      [self respondWithAccount:nil error:nil];
    } else {
      [self respondWithAccount:nil error:error.flutterError];
    }
  } else {
    NSURL* photoUrl;
    if (user.profile.hasImage) {
      // Placeholder that will be replaced by on the Dart side based on screen size
      photoUrl = [user.profile imageURLWithDimension:1337];
    }
    [self respondWithAccount:@{
                               @"displayName" : user.profile.name ?: [NSNull null],
                               @"email" : user.profile.email ?: [NSNull null],
                               @"id" : user.userID ?: [NSNull null],
                               @"photoUrl" : [photoUrl absoluteString] ?: [NSNull null],
                             }
                      error:nil];
  }
}

- (void)signIn:(GIDSignIn *)signIn
    didDisconnectWithUser:(GIDGoogleUser *)user
                withError:(NSError *)error {
  [self respondWithAccount:@{} error:nil];
}

- (void)respondWithAccount:(id)account
                    error:(NSError *)error
{
  NSArray<FlutterResultReceiver> *requests = _accountRequests;
  _accountRequests = [[NSMutableArray alloc] init];
  for (FlutterResultReceiver accountRequest in requests) {
    accountRequest(error != nil ? error.flutterError : account);
  }
}
@end

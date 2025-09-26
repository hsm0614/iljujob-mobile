//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<app_links/AppLinksIosPlugin.h>)
#import <app_links/AppLinksIosPlugin.h>
#else
@import app_links;
#endif

#if __has_include(<iamport_webview_flutter/FLTIamportWebViewFlutterPlugin.h>)
#import <iamport_webview_flutter/FLTIamportWebViewFlutterPlugin.h>
#else
@import iamport_webview_flutter;
#endif

#if __has_include(<portone_flutter/IamportFlutterPlugin.h>)
#import <portone_flutter/IamportFlutterPlugin.h>
#else
@import portone_flutter;
#endif

#if __has_include(<url_launcher_ios/URLLauncherPlugin.h>)
#import <url_launcher_ios/URLLauncherPlugin.h>
#else
@import url_launcher_ios;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [AppLinksIosPlugin registerWithRegistrar:[registry registrarForPlugin:@"AppLinksIosPlugin"]];
  [FLTIamportWebViewFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTIamportWebViewFlutterPlugin"]];
  [IamportFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"IamportFlutterPlugin"]];
  [URLLauncherPlugin registerWithRegistrar:[registry registrarForPlugin:@"URLLauncherPlugin"]];
}

@end

#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "fishhook.h"

#define VERSION "0.0.1"

static NSArray* getActiveResourcePacks(void);
static NSString* findFileInPack(NSString* packId, NSString* subpack, NSString* fileName);

// data path
static NSString* getResourcePacksPath(void) {
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    return [docPath stringByAppendingPathComponent:@"games/com.mojang/resource_packs"];
}

// hook fopen
FILE* (*orig_fopen)(const char *path, const char *mode);
FILE* hook_fopen(const char *path, const char *mode) {
    if (path != NULL) {
        NSString *nsPath = [NSString stringWithUTF8String:path];
        
        // load material.bin in pack
        if ([nsPath hasSuffix:@".material.bin"] && [nsPath containsString:@"renderer/materials"]) {
            NSString *fileName = [nsPath lastPathComponent];
            NSString *customFile = findFileInPack(nil, nil, fileName);
            if (customFile) {
                NSLog(@"[MaterialLoader] ✅ Pack: %@", customFile);
                return orig_fopen([customFile UTF8String], mode);
            }
        }
    }
    return orig_fopen(path, mode);
}

// get active pack lists
static NSArray* getActiveResourcePacks(void) {
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *globalPacksPath = [docPath stringByAppendingPathComponent:@"games/com.mojang/minecraftpe/global_resource_packs.json"];
    
    NSData *data = [NSData dataWithContentsOfFile:globalPacksPath];
    if (!data) return nil;
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

// find pack by uuid get in global_resource_packs.json
static NSString* findPackRoot(NSString* packId) {
    NSString *resPacks = getResourcePacksPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *folder in [fm contentsOfDirectoryAtPath:resPacks error:nil]) {
        NSString *manifestPath = [[resPacks stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"manifest.json"];
        NSData *data = [NSData dataWithContentsOfFile:manifestPath];
        if (!data) continue;
        
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *headerUuid = manifest[@"header"][@"uuid"];
        
        if ([headerUuid isEqualToString:packId]) {
            return [resPacks stringByAppendingPathComponent:folder];
        }
        for (NSDictionary *mod in manifest[@"modules"]) {
            if ([mod[@"uuid"] isEqualToString:packId]) {
                return [resPacks stringByAppendingPathComponent:folder];
            }
        }
    }
    return nil;
}

// find .material.bin in pack
static NSString* findFileInPack(NSString* packId, NSString* subpack, NSString* fileName) {
    NSArray *activePacks = getActiveResourcePacks();
    if (!activePacks) return nil;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSDictionary *pack in activePacks) {
        NSString *pid = packId ?: pack[@"pack_id"];
        NSString *sp = subpack ?: pack[@"subpack"] ?: @"default";
        if (!pid) continue;
        
        NSString *packRoot = findPackRoot(pid);
        if (!packRoot) continue;
        
        // subpacks
        if ([sp isEqualToString:@"default"]) {
            // default subpack: we find subpacks/default/renderer/materials first. if it does not exist, fallback to renderer/materials
            NSString *defaultPath = [[[packRoot stringByAppendingPathComponent:@"subpacks/default"]
                                      stringByAppendingPathComponent:@"renderer/materials"]
                                      stringByAppendingPathComponent:fileName];
            if ([fm fileExistsAtPath:defaultPath]) {
                return defaultPath;
            }
        } else {
            // another subpack
            NSString *subpackPath = [[[packRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"subpacks/%@", sp]]
                                      stringByAppendingPathComponent:@"renderer/materials"]
                                      stringByAppendingPathComponent:fileName];
            if ([fm fileExistsAtPath:subpackPath]) {
                return subpackPath;
            }
        }
        

        NSString *rootPath = [[packRoot stringByAppendingPathComponent:@"renderer/materials"]
                              stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:rootPath]) {
            return rootPath;
        }
    }
    return nil;
}

static void showDialog(NSString* title, NSString* message) {
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIWindow *gameWindow = nil;
    for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    gameWindow = window;
                    break;
                }
            }
            if (!gameWindow) gameWindow = windowScene.windows.firstObject;
            break;
        }
    }
    
    UIViewController *rootVC = gameWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%ctor {
    struct rebinding fopen_rebinding = {"fopen", hook_fopen, (void *)&orig_fopen};
    rebind_symbols(&fopen_rebinding, 1);
    
    if (orig_fopen) {
        NSLog(@"[MaterialLoader] ✅ fopen hooked successfully");
    } else {
        NSLog(@"[MaterialLoader] ❌ Failed to hook fopen");
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *title = @"Material Loader";
        NSString *desc = [NSString stringWithFormat:@"Version: %s\nDeveloper: congcq", VERSION];
        showDialog(title, desc);
    });
}
vậy thì viết cho tôi toàn bộ code thay bằng NSSearchPathForDirectoriesInDomains đi

#import <substrate.h>
#import <Foundation/Foundation.h>

static NSArray* getActiveResourcePacks(void);
static NSString* findFileInPack(NSString* packId, NSString* subpack, NSString* fileName);
static NSString* mergeMaterialsIndex(NSString* originalPath);

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
        
        // return merged index
        if ([nsPath hasSuffix:@"materials.index.json"]) {
            NSString *mergedPath = mergeMaterialsIndex(nsPath);
            if (mergedPath) {
                return orig_fopen([mergedPath UTF8String], mode);
            }
        }
        
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

// merge material.index.json
static NSString* mergeMaterialsIndex(NSString* originalPath) {
    NSData *originalData = [NSData dataWithContentsOfFile:originalPath];
    if (!originalData) return nil;
    
    NSDictionary *originalDict = [NSJSONSerialization JSONObjectWithData:originalData options:0 error:nil];
    if (!originalDict || ![originalDict isKindOfClass:[NSDictionary class]]) return nil;
    
    NSArray *originalMaterials = originalDict[@"materials"];
    if (!originalMaterials) return nil;
    
    NSMutableArray *merged = [originalMaterials mutableCopy];
    
    // find materials.index.json from pack
    NSString *customIndexPath = findFileInPack(nil, nil, @"materials.index.json");
    if (!customIndexPath) {
        NSLog(@"[MaterialLoader] Does not have materials.index.json in pack");
        return nil;
    }
    
    NSData *customData = [NSData dataWithContentsOfFile:customIndexPath];
    NSDictionary *customDict = [NSJSONSerialization JSONObjectWithData:customData options:0 error:nil];
    NSArray *customMaterials = customDict[@"materials"];
    
    for (NSDictionary *entry in customMaterials) {
        NSString *name = entry[@"name"];
        BOOL replaced = NO;
        for (NSInteger i = 0; i < (NSInteger)merged.count; i++) {
            if ([merged[i][@"name"] isEqualToString:name]) {
                merged[i] = entry;
                replaced = YES;
                break;
            }
        }
        if (!replaced) {
            [merged addObject:entry];
        }
    }
    
    NSDictionary *mergedDict = @{@"materials": merged};
    NSString *mergedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"materials_merged.json"];
    NSData *mergedData = [NSJSONSerialization dataWithJSONObject:mergedDict options:NSJSONWritingPrettyPrinted error:nil];
    [mergedData writeToFile:mergedPath atomically:YES];
    
    return mergedPath;
}

// main
%ctor {
    MSHookFunction((void *)fopen, (void *)hook_fopen, (void **)&orig_fopen);
    NSLog(@"[MaterialLoader] Successfully loaded");
}

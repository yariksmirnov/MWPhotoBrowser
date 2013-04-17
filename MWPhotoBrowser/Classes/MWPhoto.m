//
//  MWPhoto.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "MWPhoto.h"
#import "MWPhotoBrowser.h"
#import <objc/runtime.h>

// Private
@interface MWPhoto () {

    // Image Sources
    NSString *_photoPath;
    NSURL *_photoURL;

    // Image
    UIImage *_underlyingImage;

    // Other
    NSString *_caption;
    BOOL _loadingInProgress;
        
}

// Properties
@property (nonatomic, retain) UIImage *underlyingImage;

// Methods
- (void)imageDidFinishLoadingSoDecompress;
- (void)imageLoadingComplete;

@end

// MWPhoto
@implementation MWPhoto

// Properties
@synthesize underlyingImage = _underlyingImage, 
caption = _caption;

#pragma mark Class Methods

+ (MWPhoto *)photoWithImage:(UIImage *)image {
	return [[MWPhoto alloc] initWithImage:image];
}

+ (MWPhoto *)photoWithFilePath:(NSString *)path {
	return [[MWPhoto alloc] initWithFilePath:path];
}

+ (MWPhoto *)photoWithURL:(NSURL *)url {
	return [[MWPhoto alloc] initWithURL:url];
}

#pragma mark NSObject

- (id)initWithImage:(UIImage *)image {
	if ((self = [super init])) {
		self.underlyingImage = image;
	}
	return self;
}

- (id)initWithFilePath:(NSString *)path {
	if ((self = [super init])) {
		_photoPath = [path copy];
	}
	return self;
}

- (id)initWithURL:(NSURL *)url {
	if ((self = [super init])) {
		_photoURL = [url copy];
	}
	return self;
}

- (void)cancelCurrentLoad {
    id<SDWebImageOperation> operation = objc_getAssociatedObject(self, &_operationKey);
    if (operation)
    {
        [operation cancel];
        objc_setAssociatedObject(self, &_operationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)dealloc {
    [self cancelCurrentLoad];
}

#pragma mark MWPhoto Protocol Methods

- (UIImage *)underlyingImage {
    return _underlyingImage;
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    _loadingInProgress = YES;
    if (self.underlyingImage) {
        // Image already loaded
        [self imageLoadingComplete];
    } else {
        if (_photoPath) {
            // Load async from file
            [self performSelectorInBackground:@selector(loadImageFromFileAsync) withObject:nil];
        } else if (_photoURL) {
            // Load async from web (using SDWebImage)
            
            id<SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:_photoURL options:0 progress:NULL completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
                self.underlyingImage = image;
                if (error) {
                    MWLog(@"SDWebImage failed to download image: %@", error);
                }
                [self imageDidFinishLoadingSoDecompress];
            }];
            objc_setAssociatedObject(self, &_operationKey, operation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // Failed - no source
            self.underlyingImage = nil;
            [self imageLoadingComplete];
        }
    }
}

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
    _loadingInProgress = NO;
    [self cancelCurrentLoad];
	if (self.underlyingImage && (_photoPath || _photoURL)) {
		self.underlyingImage = nil;
	}
}

#pragma mark - Async Loading

// Called in background
// Load image in background from local file
- (void)loadImageFromFileAsync {
    @autoreleasepool {
        @try {
            NSError *error = nil;
            NSData *data = [NSData dataWithContentsOfFile:_photoPath options:NSDataReadingUncached error:&error];
            if (!error) {
                self.underlyingImage = [[UIImage alloc] initWithData:data];
            } else {
                self.underlyingImage = nil;
                MWLog(@"Photo from file error: %@", error);
            }
        } @catch (NSException *exception) {
        } @finally {
            [self performSelectorOnMainThread:@selector(imageDidFinishLoadingSoDecompress) withObject:nil waitUntilDone:NO];
        }
    }
}

// Called on main
- (void)imageDidFinishLoadingSoDecompress {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (self.underlyingImage) {
        // Decode image async to avoid lagging when UIKit lazy loads
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.underlyingImage = [UIImage decodedImageWithImage:self.underlyingImage];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self imageLoadingComplete];
            });
        });
    } else {
        // Failed
        [self imageLoadingComplete];
    }
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

@end

#import <Foundation/Foundation.h>

@interface FMIOSurfaceAccumulator : NSObject

+ (id)accumulatorWithSize:(NSSize)s CGLContext:(CGLContextObj)cglCtx pixelFormat:(CGLPixelFormatObj)pf colorSpace:(CGColorSpaceRef)colorSpace;

- (CIImage*)image;

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r;

- (CGRect)extent;

@end


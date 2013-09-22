#import <Foundation/Foundation.h>

@interface FMIOSurfaceAccumulator : NSObject

+ (id)accumulatorWithSize:(NSSize)s CGLContext:(CGLContextObj)cglCtx pixelFormat:(CGLPixelFormatObj)pf colorSpace:(CGColorSpaceRef)colorSpace;

- (CIImage*)image;

- (void)clear;
- (void)clearRect:(NSRect)r;
- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r;
- (void)compositeOverImage:(CIImage*)img dirtyRect:(CGRect)dirtyRect;

- (CGRect)extent;

@end

#import <Foundation/Foundation.h>

@interface FMIOSurfaceAccumulator : NSObject

+ (id)accumulatorWithSize:(NSSize)s colorSpace:(CGColorSpaceRef)colorSpace;

- (CIImage*)image;

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r;
- (void)sourceAtopImage:(CIImage*)im dirtyRect:(CGRect)r;

- (CGRect)extent;

- (void)clear;
- (void)clearRect:(CGRect)r;


- (void)drawOnCGContextWithBlock:(void (^)(CGContextRef context))b;

@end


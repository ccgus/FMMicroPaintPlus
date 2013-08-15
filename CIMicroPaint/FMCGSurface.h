//
//  FMCGSurface.h
//  CIMicroPaint
//
//  Created by August Mueller on 8/13/13.
//
//

#import <Foundation/Foundation.h>

@interface FMCGSurface : NSObject

+ (id)surfaceWithSize:(NSSize)s;
+ (id)iosurfaceWithSize:(NSSize)s;

- (CIImage*)CIImage;
- (CGImageRef)CGImage __attribute__((cf_returns_retained));

- (void)clear;
- (void)clearRect:(NSRect)r;
- (void)drawRect:(NSRect)r onSurfaceWithBlock:(void (^)())b;

- (BOOL)reshapeToSize:(NSSize)s;

@end

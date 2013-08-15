//
//  FMCGSurface.m
//  CIMicroPaint
//
//  Created by August Mueller on 8/13/13.
//
//

#import "FMCGSurface.h"

@interface FMCGSurface ()

@property (assign) CGContextRef bitmapContext;
@property (assign) IOSurfaceRef ioSurface;
@property (assign) BOOL ioSurfaceBacked;

@end

@implementation FMCGSurface

+ (id)surfaceWithSize:(NSSize)s {
    
    FMCGSurface *surf = [FMCGSurface new];
    
    [surf createContextOfSize:s];
    
    return surf;
}

+ (id)iosurfaceWithSize:(NSSize)s {
    
    FMCGSurface *surf = [FMCGSurface new];
    
    [surf setIoSurfaceBacked:YES];
    
    [surf createContextOfSize:s];
    
    return surf;
}

- (void)dealloc {
    
    if (_bitmapContext) {
        CGContextRelease(_bitmapContext);
    }
    
    if (_ioSurface) {
        CFRelease(_ioSurface);
    }
    
}

- (CGImageRef)CGImage {
    return CGBitmapContextCreateImage(_bitmapContext);
}

- (CIImage*)CIImage {
    CGImageRef r = [self CGImage];
    CIImage *c = [CIImage imageWithCGImage:r];
    CGImageRelease(r);
    return c;
}

- (void)clear {
    [self clearRect:NSMakeRect(0, 0, CGBitmapContextGetWidth(_bitmapContext), CGBitmapContextGetHeight(_bitmapContext))];
}

- (void)clearRect:(NSRect)r {
    CGContextClearRect(_bitmapContext, r);
}

- (void)drawRect:(NSRect)dirtyRect onSurfaceWithBlock:(void (^)())b {
    
    CGContextSaveGState(_bitmapContext);
    CGContextClearRect(_bitmapContext, dirtyRect);
    CGContextClipToRect(_bitmapContext, dirtyRect);
    
    NSGraphicsContext *currentNSContext = [NSGraphicsContext graphicsContextWithGraphicsPort:_bitmapContext flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:currentNSContext];
    b();
    [NSGraphicsContext restoreGraphicsState];
    
    CGContextRestoreGState(_bitmapContext);
}

- (void)createContextOfSize:(NSSize)s {
    
    if (_bitmapContext) {
        CGContextRelease(_bitmapContext);
    }
    
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    
    CGContextRef ctx = nil;;
    
    
    if (_ioSurfaceBacked) {
        
        if (_ioSurface) {
            CFRelease(_ioSurface);
        }
        
        _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)@{(id)kIOSurfaceWidth: @(s.width),
                                                                 (id)kIOSurfaceHeight: @(s.height),
                                                                 (id)kIOSurfaceBytesPerElement: @(8)
                                                                 });
        
        ctx = CGBitmapContextCreate(IOSurfaceGetBaseAddress(_ioSurface),
                                    IOSurfaceGetWidth(_ioSurface),
                                    IOSurfaceGetHeight(_ioSurface),
                                    IOSurfaceGetBytesPerElement(_ioSurface),
                                    IOSurfaceGetBytesPerRow(_ioSurface),
                                    cs,
                                    kCGImageAlphaPremultipliedFirst);
        
    }
    else {
        ctx = CGBitmapContextCreate(nil, s.width, s.height, 8, 0, cs, kCGImageAlphaPremultipliedFirst);
    }
    
    CGColorSpaceRelease(cs);
    
    assert(ctx);
    
    _bitmapContext = ctx;
}

- (BOOL)reshapeToSize:(NSSize)s {
    
    if (CGBitmapContextGetWidth(_bitmapContext) < s.width || CGBitmapContextGetHeight(_bitmapContext) < s.height) {
        
        [self createContextOfSize:s];
        return YES;
    }
    
    return NO;
}


@end

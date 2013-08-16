//
//  FMCGSurface.m
//  CIMicroPaint
//
//  Created by August Mueller on 8/13/13.
//
//

#import "FMCGSurface.h"
#import <QuartzCore/QuartzCore.h>

@interface FMCGSurface ()

@property (assign) CGContextRef bitmapContext;
@property (assign) IOSurfaceRef ioSurface;
@property (assign) BOOL ioSurfaceBacked;
@property (strong) CIFilter *blendFilter;
@property (strong) CIContext *context;
@property (assign) CGColorSpaceRef colorspace;

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
    
    if (_colorspace) {
        CGColorSpaceRelease(_colorspace);
    }
    
}

- (CGImageRef)CGImage {
    return CGBitmapContextCreateImage(_bitmapContext);
}

- (CIImage*)image {
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
    
    if (!_colorspace) {
        _colorspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    }
    
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
                                    _colorspace,
                                    kCGImageAlphaPremultipliedFirst);
        
    }
    else {
        ctx = CGBitmapContextCreate(nil, s.width, s.height, 8, 0, _colorspace, kCGImageAlphaPremultipliedFirst);
    }
    
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

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r {
    
    assert(_ioSurface);
    assert(_colorspace);
    
    if (!_context) {
        [self setContext:[CIContext contextWithCGContext:_bitmapContext options:@{}]];
    }
    
    im = [im imageByCroppingToRect:NSIntegralRectWithOptions(r, NSAlignAllEdgesOutward)];
    
    
    [_context drawImage:im inRect:r fromRect:r];
    
    //[_context render:im toIOSurface:_ioSurface bounds:[self extent] colorSpace:_colorspace];
    //[_context render:im toBitmap:IOSurfaceGetBaseAddress(_ioSurface) rowBytes:IOSurfaceGetBytesPerRow(_ioSurface) bounds:[self extent] format:kCIFormatARGB8 colorSpace:_colorspace];
}

- (void)compositeOverImage:(CIImage*)img dirtyRect:(CGRect)dirtyRect {
    
    if (!_blendFilter) {
        [self setBlendFilter:[CIFilter filterWithName:@"CISourceOverCompositing"]];
    }
    
    
    [_blendFilter setValue:[self image] forKey:kCIInputBackgroundImageKey];
    [_blendFilter setValue:img forKey:kCIInputImageKey];
    
    
    [self setImage:[_blendFilter valueForKey:kCIOutputImageKey] dirtyRect:dirtyRect];
}

- (CGRect)extent {
    return CGRectMake(0, 0, CGBitmapContextGetWidth(_bitmapContext), CGBitmapContextGetHeight((_bitmapContext)));
}

@end

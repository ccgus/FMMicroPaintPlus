
#import "FMIOSurfaceAccumulator.h"
#import <QuartzCore/QuartzCore.h>
#import <GLUT/glut.h>

@interface FMIOSurfaceAccumulator ()

@property (assign) IOSurfaceRef ioSurface;

@property (strong) CIContext *context;
@property (strong) CIRenderDestination *renderDest;
@property (assign) CGContextRef bitmapContext;
@property (strong) CIImage *lastImage;
@property (assign) CGColorSpaceRef colorSpace;
@property (assign) NSSize size;

@end

@implementation FMIOSurfaceAccumulator


+ (id)accumulatorWithSize:(NSSize)s colorSpace:(CGColorSpaceRef)colorSpace; {
    
    FMIOSurfaceAccumulator *surf = [FMIOSurfaceAccumulator new];
    
    [surf setColorSpace:CGColorSpaceRetain(colorSpace)];
    
    [surf createContextOfSize:s];
    
    return surf;
}

- (void)dealloc {
    
    if (_ioSurface) {
        CFRelease(_ioSurface);
    }
    
    if (_colorSpace) {
        CGColorSpaceRelease(_colorSpace);
    }
}

- (void)createContextOfSize:(NSSize)s {
    
    _size = s;
    
    size_t alignment = 16;
    size_t bpr       = (((size_t)s.width * 4) + (alignment -1)) & ~(alignment-1);
    
    NSDictionary * opts = @{(id)kIOSurfaceWidth: @(s.width),
                            (id)kIOSurfaceHeight: @(s.height),
                            (id)kIOSurfaceBytesPerElement: @(4),
                            (id)kIOSurfaceBytesPerRow: @(bpr),
                            (id)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)
                            };
    
    assert(!_ioSurface);
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)opts);
    
    _context = [CIContext contextWithOptions:@{}];
    
    _renderDest = [[CIRenderDestination alloc] initWithIOSurface:(__bridge IOSurface * _Nonnull)(_ioSurface)];
    [_renderDest setColorSpace:_colorSpace];
    
    
}


- (CIImage*)image {
    
    if (_lastImage) {
        return _lastImage;
    }
    
    _lastImage = [CIImage imageWithIOSurface:_ioSurface options:@{(id)kCIImageColorSpace: (__bridge id)_colorSpace}];
    
    return _lastImage;
}

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r {
    
    _lastImage = nil;
    
    r = NSIntegralRect(r);
    
    NSError *outErr;
    CIRenderTask *renderTask = [_context startTaskToRender:[im imageByCroppingToRect:r] toDestination:_renderDest error:&outErr];
    [renderTask waitUntilCompletedAndReturnError:&outErr];
    
    
}

- (void)sourceAtopImage:(CIImage*)im dirtyRect:(CGRect)r {
    
    _lastImage = nil;
    
    [_renderDest setBlendKernel:[CIBlendKernel sourceOver]];
    
    r = NSIntegralRect(r);
    
    NSError *outErr;
    CIRenderTask *renderTask = [_context startTaskToRender:[im imageByCroppingToRect:r] toDestination:_renderDest error:&outErr];
    [renderTask waitUntilCompletedAndReturnError:&outErr];
    
    [_renderDest setBlendKernel:nil];
    
}

- (CGRect)extent {
    return CGRectMake(0, 0, _size.width, _size.height);
}

- (void)setupBitmapContext {
    
    if (_bitmapContext) {
        return;
    }
    
    uint32_t bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    uint32_t bpc = 8;
    uint32_t seed;
    IOSurfaceLock(_ioSurface, 0, &seed);
    
    _bitmapContext = CGBitmapContextCreate(IOSurfaceGetBaseAddress(_ioSurface),
                                           IOSurfaceGetWidth(_ioSurface),
                                           IOSurfaceGetHeight(_ioSurface),
                                           bpc,
                                           IOSurfaceGetBytesPerRow(_ioSurface),
                                           _colorSpace,
                                           bitmapInfo);
    
    IOSurfaceUnlock(_ioSurface, 0, &seed);
}

- (void)drawOnCGContextWithBlock:(void (^)(CGContextRef context))b {
    
    [self setupBitmapContext];
    
    IOSurfaceLock(_ioSurface, 0, nil);
    
    CGContextSaveGState(_bitmapContext);
    
    NSGraphicsContext *currentNSContext = [NSGraphicsContext graphicsContextWithGraphicsPort:_bitmapContext flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:currentNSContext];
    b(_bitmapContext);
    [NSGraphicsContext restoreGraphicsState];
    
    CGContextRestoreGState(_bitmapContext);
    
    IOSurfaceUnlock(_ioSurface, 0, nil);
    
    _lastImage = nil;
}



- (void)clear {
    [self clearRect:[self extent]];
}

- (void)clearRect:(CGRect)r {
    
    // There's two ways to do this.
    // The first is via CG like so:
    //
    //    IOSurfaceLock(_ioSurface, 0, nil);
    //    CGContextClearRect(context, r);
    //    IOSurfaceUnlock(_ioSurface, 0, nil);
    //
    // Or you can stay in CI Land:
    
    static CIImage *clearImage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        CIFilter *transparent = [CIFilter filterWithName:@"CIConstantColorGenerator"];
        
        [transparent setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:kCIInputColorKey];
        
        clearImage = [transparent outputImage];
    });
    
    [self setImage:clearImage dirtyRect:r];
}

@end


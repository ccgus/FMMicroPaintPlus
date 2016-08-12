#import "FMCIView.h"

#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import "FMCGSurface.h"
#import "FMIOSurfaceAccumulator.h"

@interface FMCIView ()

@property (nonatomic, strong) CIContext *context;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@property (nonatomic, strong) NSDictionary *contextOptions;
@property (nonatomic, strong) CIImageAccumulator *imageAccumulator;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, strong) CIFilter *brushFilter;
@property (nonatomic, strong) CIFilter *compositeFilter;
@property (nonatomic, strong) CIFilter *gradientFilter;
@property (nonatomic, strong) CIImage *scaledImage;
@property (nonatomic, strong) FMCGSurface *hudSurface;
@property (assign) CGFloat scale;
@property (assign) CGFloat retinaScale;
@property (assign) CGFloat filterRadius;
@property (assign) NSPoint filterCenter;
@property (assign) NSPoint canvasTranslate;
@property (assign) BOOL movingFilter;
@property (assign) CGColorSpaceRef imageColorSpace;
@property (assign) CGContextRef ioCGContext;

@end

@implementation FMCIView



- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _scale          = 1.0;
        _retinaScale    = 1.0;
        _color          = [NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:1.0];
        
        _brushFilter    = [CIFilter filterWithName: @"CIRadialGradient" keysAndValues:
                           @"inputColor1", [CIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0],
                           @"inputRadius0", @0.0, nil];
        
        _compositeFilter = [CIFilter filterWithName: @"CISourceOverCompositing"];
        _gradientFilter  = [CIFilter filterWithName:@"CIRadialGradient"];
        
        if ([[NSUserDefaults standardUserDefaults] floatForKey:@"brushSize"] < 1) {
            [[NSUserDefaults standardUserDefaults] setFloat:25 forKey:@"brushSize"];
        }
        
    }
    
    return self;
}


- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_imageColorSpace) {
        CGColorSpaceRelease(_imageColorSpace);
    }
    
}

- (void)awakeFromNib {
    
    [self displayProfileChanged:nil];
    
    [self prepareMetal];
    
    [[[self enclosingScrollView] contentView] setCopiesOnScroll:NO];
    
    [[self window] setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
    
	[[self window] makeFirstResponder:self];
    
    CIImage *baseImage = [CIImage imageWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"aoraki-90388.jpg"]];
    
    CGColorSpaceRef colorSpace = [baseImage colorSpace];
    if (colorSpace) {
        _imageColorSpace = CGColorSpaceRetain(colorSpace);
    }
    else {
        _imageColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    }
    
    [self setFrame:[baseImage extent]];
    
    CIImageAccumulator *acc = [[CIImageAccumulator alloc] initWithExtent:[baseImage extent] format:kCIFormatRGBA16];
    
    //CIImageAccumulator *acc = (CIImageAccumulator*)[FMCGSurface iosurfaceWithSize:[baseImage extent].size CGLContext:[[self openGLContext] CGLContextObj] pixelFormat:[pixelFormat CGLPixelFormatObj] colorSpace:colorSpace];
    //CIImageAccumulator *acc = (CIImageAccumulator*)[FMCGSurface surfaceWithSize:[baseImage extent].size];
    /*
    CIImageAccumulator *acc = (CIImageAccumulator*)[FMCGSurface glSurfaceWithSize:[baseImage extent].size
                                                                       CGLContext:[[self openGLContext] CGLContextObj]
                                                                      pixelFormat:[pixelFormat CGLPixelFormatObj]
                                                                       colorSpace:colorSpace];
    */
    /*
    CIImageAccumulator *acc = (CIImageAccumulator*)[FMIOSurfaceAccumulator accumulatorWithSize:[baseImage extent].size
                                                                       CGLContext:[[self openGLContext] CGLContextObj]
                                                                      pixelFormat:[pixelFormat CGLPixelFormatObj]
                                                                       colorSpace:_imageColorSpace];
    */
    //CGColorSpaceRelease(colorSpace);
    
    [acc setImage:baseImage dirtyRect:[baseImage extent]];
    
    [self setImageAccumulator:acc];
    
    [self setNeedsDisplay:YES];
    
    [self scrollPoint:NSZeroPoint];
    
    [self setFilterRadius:[baseImage extent].size.height/2];
    
    [_gradientFilter setValue:@(0) forKey:@"inputRadius0"];
    [_gradientFilter setValue:@([self filterRadius]) forKey:@"inputRadius1"];
    [_gradientFilter setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:@"inputColor0"];
    [_gradientFilter setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:.2] forKey:@"inputColor1"];
    
    _filterCenter = NSMakePoint(NSMidX([baseImage extent]), NSMidY([baseImage extent]));
    
    [self takeScaleValueFrom:@(1.0)];
    
}

- (void)setContextOptions:(NSDictionary *)dict {
    _contextOptions = dict;
    [self setContext:nil];
}

- (void)prepareMetal {
    
    // [self setColorPixelFormat:MTLPixelFormatRGBA16Float];
    
    [self setDepthStencilPixelFormat:MTLPixelFormatA8Unorm];
    
    // Set the view to use the default device
    [self setDevice:MTLCreateSystemDefaultDevice()];
    
    // Create a new command queue
    _commandQueue = [[self device] newCommandQueue];
    
    _context = [CIContext contextWithMTLDevice:[self device]];
    
    [self setFramebufferOnly:NO];
    [self setEnableSetNeedsDisplay:YES];
    
}


- (void)updateMatrices {
    
    NSRect visibleRect = [[[self enclosingScrollView] contentView] documentVisibleRect];
    
    if (!NSEqualRects(visibleRect, _lastBounds)) {
        
        
        //[[self openGLContext] update];
		
        
		_lastBounds = visibleRect;
    }
}


- (BOOL)displaysWhenScreenProfileChanges {
    return YES;
}


- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:nil];
    [center addObserver:self selector:@selector(displayProfileChanged:) name:NSWindowDidChangeScreenProfileNotification object:newWindow];
    [center addObserver:self selector:@selector(displayProfileChanged:) name:NSWindowDidMoveNotification object:newWindow];
    
    // When using OpenGL, we should disable the window's "one-shot" feature
    [newWindow setOneShot:NO];
}


- (void)displayProfileChanged:(NSNotification*)notification {
	CGDirectDisplayID oldDid = _directDisplayID;
	_directDisplayID = (CGDirectDisplayID)[[[[[self window] screen] deviceDescription] objectForKey:@"NSScreenNumber"] pointerValue];
    
	if (_directDisplayID == oldDid) {
		return;
	}
    
    _retinaScale = [[self window] convertRectToBacking:NSMakeRect(1, 1, 1, 1)].size.width;
    
}

- (void)drawRect:(NSRect)updateRect {
    
    
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    @autoreleasepool {
        
        /*
        id <MTLRenderCommandEncoder> renderCommandEncocer = [commandBuffer renderCommandEncoderWithDescriptor:[MTLRenderPassDescriptor renderPassDescriptor]];
        
        MTLScissorRect scissorRect;
        scissorRect.x = updateRect.origin.x;
        scissorRect.y = updateRect.origin.y;
        scissorRect.width = updateRect.size.width;
        scissorRect.height = updateRect.size.height;
        
        [renderCommandEncocer setScissorRect:scissorRect];
        */
        
        NSRect visibleRect = [[[self enclosingScrollView] contentView] documentVisibleRect];
        
        
        CIImage *img = [[self imageAccumulator] image];
        
        [_gradientFilter setValue:[CIVector vectorWithX:_filterCenter.x Y:_filterCenter.y] forKey:kCIInputCenterKey];
        
        static CIFilter *backgroundFilter = nil;
        if (!backgroundFilter) {
            backgroundFilter = [CIFilter filterWithName:@"CIConstantColorGenerator" keysAndValues:@"inputColor", [CIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0], nil];
        }
        
        static CIFilter *compFilter = nil;
        if (!compFilter) {
            compFilter = [CIFilter filterWithName: @"CISourceOverCompositing"];
        }
        
        
        if (!_scaledImage) {
            
            static CIFilter *gradientCompFilter = nil;
            if (!gradientCompFilter) {
                gradientCompFilter = [CIFilter filterWithName: @"CISourceOverCompositing"];
            }
            
            [gradientCompFilter setValue:[_gradientFilter valueForKey:kCIOutputImageKey] forKey:kCIInputImageKey];
            [gradientCompFilter setValue:img forKey:kCIInputBackgroundImageKey];
            
            img = [gradientCompFilter valueForKey:kCIOutputImageKey];
            
            //[self setScaledImage:img];
            [self setScaledImage:[img imageByApplyingTransform:CGAffineTransformMakeScale(_scale, _scale)]];
        }
        
        [compFilter setValue:_scaledImage forKey:kCIInputImageKey];
        [compFilter setValue:[backgroundFilter valueForKey:kCIOutputImageKey] forKey:kCIInputBackgroundImageKey];
        
        img = [compFilter valueForKey:kCIOutputImageKey];
        
        /*
         if ([[NSUserDefaults standardUserDefaults] boolForKey:@"showHUD"]) {
         
         [self drawHUDRect:glClipRect];
         
         [compFilter setValue:[_hudSurface image] forKey:kCIInputImageKey];
         [compFilter setValue:img forKey:kCIInputBackgroundImageKey];
         img = [compFilter valueForKey:kCIOutputImageKey];
         }*/
        
        //img = [img imageByCroppingToRect:visibleRect];
        img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-visibleRect.origin.x, -visibleRect.origin.y)];
        
        img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(_canvasTranslate.x, _canvasTranslate.y)];
        
        //debug(@"updateRect: %@", NSStringFromRect(updateRect));
        
        NSRect drawRect = updateRect;
        
        drawRect = NSIntersectionRect(updateRect, [[self enclosingScrollView] documentVisibleRect]);
        drawRect.size.width  *= _retinaScale;
        drawRect.size.height *= _retinaScale;
        drawRect.origin.x    *= _retinaScale;
        drawRect.origin.y    *= _retinaScale;
        
        
        drawRect = NSMakeRect(0, 0, 100, 100);
        debug(@"drawRect: %@", NSStringFromRect(drawRect));
        //debug(@"[[self enclosingScrollView] documentVisibleRect]: %@", NSStringFromRect([[self enclosingScrollView] documentVisibleRect]));
        
        //[_context render:img toIOSurface:[[[self currentDrawable] texture] iosurface] bounds:drawRect colorSpace:_imageColorSpace];
        [_context render:[img imageByCroppingToRect:drawRect] toMTLTexture:[[self currentDrawable] texture] commandBuffer:commandBuffer bounds:drawRect colorSpace:_imageColorSpace];
        
        //[self strokeRect:drawRect toMTLTexture:[[self currentDrawable] texture]];
    }
    
    [commandBuffer presentDrawable:[self currentDrawable]];
    
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

- (BOOL)isFlipped {
    return NO;
}



- (void)strokeRect:(NSRect)r toMTLTexture:(id<MTLTexture>)texture {
    
    if (!_ioCGContext) {
        
        assert([texture iosurface]);
        
        
        _ioCGContext = CGBitmapContextCreate(IOSurfaceGetBaseAddress([texture iosurface]),
                                              IOSurfaceGetWidth([texture iosurface]),
                                              IOSurfaceGetHeight([texture iosurface]),
                                              IOSurfaceGetBytesPerElement([texture iosurface]),
                                              IOSurfaceGetBytesPerRow([texture iosurface]),
                                              _imageColorSpace,
                                              kCGImageAlphaPremultipliedLast);
        
    }
    
    CGContextStrokeRect(_ioCGContext, r);
    
    /*
    glColor3f(0.0, 1.0, 0.0);
    glBegin(GL_LINE_LOOP);
    
    glVertex3f(NSMinX(r), NSMinY(r), 0.0f); // The bottom left corner
    glVertex3f(NSMinX(r), NSMaxY(r), 0.0f); // The top left corner
    glVertex3f(NSMaxX(r), NSMaxY(r), 0.0f); // The top right corner
    glVertex3f(NSMaxX(r), NSMinY(r), 0.0f); // The bottom right corner
    
    glEnd();*/
}


- (NSPoint)transformCanvasPointToView:(NSPoint)p {
    
    p.x  = p.x / _retinaScale;
    p.y  = p.y / _retinaScale;
    
    p.x  = p.x * _scale;
    p.y  = p.y * _scale;
    
    p.x += _canvasTranslate.x;
    p.y += _canvasTranslate.y;
    
    return p;
}

- (NSPoint)transformViewPointToCanvas:(NSPoint)p {
    
    p.x -= _canvasTranslate.x;
    p.y -= _canvasTranslate.y;
    
    p.x  = p.x / _scale;
    p.y  = p.y / _scale;
    
    p.x  = p.x * _retinaScale;
    p.y  = p.y * _retinaScale;
    
    return p;
    
}

- (NSRect)transformCanvasRectToView:(NSRect)r {
    
    
    r.origin.x      = r.origin.x / _retinaScale;
    r.origin.y      = r.origin.y / _retinaScale;
    r.size.width    = r.size.width  / _retinaScale;
    r.size.height   = r.size.height / _retinaScale;
    
    
    r.origin.x      = floor(r.origin.x * _scale);
    r.origin.y      = floor(r.origin.y * _scale);
    r.size.width    = ceil(r.size.width  * _scale);
    r.size.height   = ceil(r.size.height * _scale);
    
    r.origin.x += _canvasTranslate.x;
    r.origin.y += _canvasTranslate.y;
    
    return r;
}



- (void)mouseUp:(NSEvent *)event {
    
    
    _movingFilter = NO;
    [[self window] invalidateCursorRectsForView:self];
}

- (void)mouseDown:(NSEvent *)event {
    
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect filterCenterBox = [self viewRectForFilterCenter];
    
    if (NSPointInRect(loc, filterCenterBox)) {
        _movingFilter = YES;
    }
    
}

- (void)mouseDragged:(NSEvent *)event {
    
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    
    loc = [self transformViewPointToCanvas:loc];
    
    if (_movingFilter) {
        _filterCenter = loc;
        [self setScaledImage:nil];
        [self setNeedsDisplay:YES];
        return;
    }
    
    if ([NSEvent modifierFlags] & NSCommandKeyMask) {
        
        NSPoint offset = NSMakePoint([event deltaX], [event deltaY]);
        
        
        NSPoint currentScrollPosition = [[[self enclosingScrollView] contentView] bounds].origin;
                
        currentScrollPosition.x -= offset.x;
        currentScrollPosition.y += offset.y;
        
        [[[self enclosingScrollView] documentView] scrollPoint:currentScrollPosition];
        
        return;
                
    }
    
    CGFloat brushSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"brushSize"];
    
    CIFilter *brushFilter = [self brushFilter];
    
    [brushFilter setValue:@(brushSize)     forKey:@"inputRadius1"];
    [brushFilter setValue:@(brushSize - 2) forKey:@"inputRadius0"];
    
    CIColor *cicolor = [[CIColor alloc] initWithColor:_color];
    [brushFilter setValue:cicolor forKey:@"inputColor0"];
    
    CIVector *inputCenter = [CIVector vectorWithX:loc.x Y:loc.y];
    [brushFilter setValue:inputCenter forKey:@"inputCenter"];
    
    CIFilter *compositeFilter = [self compositeFilter];
    
    [compositeFilter setValue:[brushFilter valueForKey:@"outputImage"] forKey:@"inputImage"];
    [compositeFilter setValue:[[self imageAccumulator] image] forKey:@"inputBackgroundImage"];
    
    CGRect rect = CGRectMake(loc.x-brushSize, loc.y-brushSize, 2.0*brushSize, 2.0*brushSize);
    
    //[[self imageAccumulator] compositeOverImage:[brushFilter valueForKey:@"outputImage"] dirtyRect:rect];
    [[self imageAccumulator] setImage:[compositeFilter valueForKey:@"outputImage"] dirtyRect:rect];
    
    [self setScaledImage:nil];
    
    [self setNeedsDisplayInRect:[self transformCanvasRectToView:rect]];
    
    [self autoscroll:event];
    
}

- (IBAction)takeScaleValueFrom:(id)sender {
    
    CGFloat newScale = [sender floatValue];
    
    if (newScale > 20) {
        newScale *= 4;
    }
    else if (newScale > 10) {
        newScale *= 3;
    }
    else if (newScale > 5) {
        newScale *= 2;
    }
    
    [self setScale:newScale];
    
    [self setScaledImage:nil];
    
    [self setNeedsDisplay:YES];
    
    NSRect originalFrame = [[self imageAccumulator] extent];
    
    NSRect newFrame = NSMakeRect(0, 0, originalFrame.size.width * _scale, originalFrame.size.height * _scale);
    
    newFrame = NSIntegralRectWithOptions(newFrame, NSAlignAllEdgesOutward);
    
    //[self setFrame:newFrame];
    
    [_scaleField setStringValue:[NSString stringWithFormat:@"%ld%%", (NSInteger)(_scale * 100)]];
    
    [[self window] invalidateCursorRectsForView:self];

}

- (void)drawHUDRect:(NSRect)dirtyRect {
    
    if (!_hudSurface) {
        [self setHudSurface:[FMCGSurface surfaceWithSize:[[self enclosingScrollView] bounds].size]];
    }
    
    NSRect visibleRect = [[self enclosingScrollView] bounds];
    
    if ([_hudSurface reshapeToSize:visibleRect.size]) {
        dirtyRect = visibleRect;
    }
    
    [_hudSurface drawRect:dirtyRect onSurfaceWithBlock:^{
        
        [[NSColor colorWithCalibratedWhite:0.0 alpha:.5] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect([self viewRectForFilterCenter], 1, 1)] fill];
        
        [[NSColor whiteColor] set];
        
        [[NSBezierPath bezierPathWithOvalInRect:[self viewRectForFilterCenter]] stroke];
        [[NSBezierPath bezierPathWithOvalInRect:[self viewRectForFilterOutsideOval]] stroke];
        
    }];
    
}

- (NSRect)viewRectForFilterCenter {
    
    NSPoint p = [self transformCanvasPointToView:_filterCenter];
    
    return NSMakeRect(p.x - 5, p.y - 5, 20, 20);
}

- (NSRect)viewRectForFilterOutsideOval {
    CGFloat h = [self filterRadius];
    return [self transformCanvasRectToView:NSMakeRect(_filterCenter.x - h, _filterCenter.y - h, h *  2, h * 2)];
}

- (void)resetCursorRects {
    [self addCursorRect:[self viewRectForFilterCenter] cursor:[NSCursor openHandCursor]];
}


@end

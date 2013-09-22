//
//  FMCGSurface.m
//  CIMicroPaint
//
//  Created by August Mueller on 8/13/13.
//
//

#import "FMCGSurface.h"
#import <QuartzCore/QuartzCore.h>
#import <GLUT/glut.h>

enum FMCGSurfaceRenderLocation {
    FMCGSurfaceRenderLocationCPU = 1,
    FMCGSurfaceRenderLocationTexture = 2,
    FMCGSurfaceRenderLocationIOSurface = 3,
};

typedef enum FMCGSurfaceRenderLocation FMCGSurfaceRenderLocation;


@interface FMCGSurface ()

@property (assign) CGContextRef bitmapContext;
@property (assign) IOSurfaceRef ioSurface;

@property (assign) FMCGSurfaceRenderLocation renderLocation;

@property (strong) CIFilter *blendFilter;
@property (strong) CIContext *context;
@property (assign) CGColorSpaceRef colorSpace;
@property (strong) NSData *bitmapData;

@property (assign) CGLContextObj cglContext;
@property (assign) CGLPixelFormatObj cglPixelFormat;

@property (assign) BOOL hasSetupFBO;
@property (assign) GLuint FBOid;
@property (assign) GLuint FBOTextureId;
@property (assign) NSSize size;
@property (assign) CVPixelBufferRef cvPixelBuffer;
@end

@implementation FMCGSurface

+ (id)surfaceWithSize:(NSSize)s {
    
    FMCGSurface *surf = [FMCGSurface new];
    
    [surf setRenderLocation:FMCGSurfaceRenderLocationCPU];
    [surf createContextOfSize:s];
    
    return surf;
}

+ (id)iosurfaceWithSize:(NSSize)s CGLContext:(CGLContextObj)cglCtx pixelFormat:(CGLPixelFormatObj)pf colorSpace:(CGColorSpaceRef)colorSpace {
    
    FMCGSurface *surf = [FMCGSurface new];
    
    [surf setRenderLocation:FMCGSurfaceRenderLocationIOSurface];
    
    [surf setColorSpace:CGColorSpaceRetain(colorSpace)];
    [surf setCglContext:cglCtx];
    [surf setCglPixelFormat:pf];
    
    [surf createContextOfSize:s];
    
    
    return surf;
}


+ (id)glSurfaceWithSize:(NSSize)s CGLContext:(CGLContextObj)cglCtx pixelFormat:(CGLPixelFormatObj)pf colorSpace:(CGColorSpaceRef)colorSpace {
    
    FMCGSurface *surf = [FMCGSurface new];
    
    [surf setRenderLocation:FMCGSurfaceRenderLocationTexture];
    
    [surf setCglContext:cglCtx];
    [surf setCglPixelFormat:pf];
    [surf setColorSpace:CGColorSpaceRetain(colorSpace)];
    
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
    
    if (_colorSpace) {
        CGColorSpaceRelease(_colorSpace);
    }
    
    if (_cvPixelBuffer) {
        CVPixelBufferRelease(_cvPixelBuffer);
    }
    
    if (_FBOTextureId) {
        glDeleteTextures(1, &_FBOTextureId);
    }
    
	if (_FBOid) {
        glDeleteFramebuffersEXT(1, &_FBOid);
    }
    
    
}

- (CGImageRef)createCGImageWithNoFaults __attribute__((cf_returns_retained)) {
    
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(_bitmapContext);
    size_t bitsPerComp = CGBitmapContextGetBitsPerComponent(_bitmapContext);
    size_t bitsPerPixl = CGBitmapContextGetBitsPerPixel(_bitmapContext);
    
    CGBitmapInfo bitmapInfo = CGBitmapContextGetBitmapInfo(_bitmapContext);
    
    NSData *d = [NSData dataWithBytesNoCopy:CGBitmapContextGetData(_bitmapContext) length:bytesPerRow * CGBitmapContextGetHeight(_bitmapContext) freeWhenDone:NO];
    
    CGDataProviderRef dp = CGDataProviderCreateWithCFData((__bridge CFDataRef)d);
    
    CGImageRef r = CGImageCreate([self extent].size.width, [self extent].size.height, bitsPerComp, bitsPerPixl, bytesPerRow, _colorSpace, bitmapInfo, dp, 0x00, false, kCGRenderingIntentDefault);
    
    CGDataProviderRelease(dp);
    
    return r;
}

- (CGImageRef)CGImage __attribute__((cf_returns_retained)) {
    return CGBitmapContextCreateImage(_bitmapContext);
}

- (void)clear {
    [self clearRect:[self extent]];
}

- (void)clearRect:(NSRect)r {
    CGContextClearRect(_bitmapContext, r);
}

- (void)drawRect:(NSRect)dirtyRect onSurfaceWithBlock:(void (^)())b {
    
    assert(_renderLocation == FMCGSurfaceRenderLocationCPU);
    
//    if (!_bitmapContext && (_renderLocation == FMCGSurfaceRenderLocationIOSurface)) {
//        _bitmapContext = CGBitmapContextCreate(IOSurfaceGetBaseAddress(_ioSurface),
//                                               IOSurfaceGetWidth(_ioSurface),
//                                               IOSurfaceGetHeight(_ioSurface),
//                                               IOSurfaceGetBytesPerElement(_ioSurface),
//                                               IOSurfaceGetBytesPerRow(_ioSurface),
//                                               _colorSpace,
//                                               kCGImageAlphaPremultipliedLast);
//        
//        
//        [self setContext:[CIContext contextWithCGContext:_bitmapContext options:@{}]];
//    }
    
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

- (void)checkErr:(int)step {
    GLenum error = glGetError();
    if(error != GL_NO_ERROR) {
        NSLog(@"%d error = %d", step, error);
    }
}

- (void)createContextOfSize:(NSSize)s {
    
    _size = s;
    
    if (_bitmapContext) {
        CGContextRelease(_bitmapContext);
    }
    
    if (!_colorSpace) {
        _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    }
    
    if (_renderLocation == FMCGSurfaceRenderLocationTexture) {
        _context = [CIContext contextWithCGLContext:_cglContext pixelFormat:_cglPixelFormat colorSpace:_colorSpace options:nil];
    }
    else if (_renderLocation == FMCGSurfaceRenderLocationIOSurface) {
        
        if (_ioSurface) {
            CFRelease(_ioSurface);
        }
        
        // pixel format is in CVPixelBuffer.h!
        
        size_t alignment = 16;
        size_t bpr       = (((size_t)s.width * 4) + (alignment -1)) & ~(alignment-1);
        
        NSDictionary * opts = @{(id)kIOSurfaceWidth: @(s.width),
                                (id)kIOSurfaceHeight: @(s.height),
                                (id)kIOSurfaceBytesPerElement: @(4),
                                (id)kIOSurfaceBytesPerRow: @(bpr),
                                (id)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
                                };
        
        _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)opts);
        
        assert(_ioSurface);
        
        //        ctx = CGBitmapContextCreate(IOSurfaceGetBaseAddress(_ioSurface),
        //                                    IOSurfaceGetWidth(_ioSurface),
        //                                    IOSurfaceGetHeight(_ioSurface),
        //                                    IOSurfaceGetBytesPerElement(_ioSurface),
        //                                    IOSurfaceGetBytesPerRow(_ioSurface),
        //                                    _colorSpace,
        //                                    bitmapInfo);
        
        //_context = [CIContext new];
        _context = [CIContext contextWithCGLContext:_cglContext pixelFormat:_cglPixelFormat colorSpace:_colorSpace options:nil];
        
    }
    else {
        _bitmapContext = CGBitmapContextCreate(nil, s.width, s.height, 8, 0, _colorSpace, kCGImageAlphaPremultipliedFirst);
        
        [self setContext:[CIContext contextWithCGContext:_bitmapContext options:@{}]];
        
    }
    
}

- (BOOL)reshapeToSize:(NSSize)s {
    
    if (_size.width < s.width || _size.height < s.height) {
        
        [self createContextOfSize:s];
        return YES;
    }
    
    return NO;
}

- (CIImage*)image {
    
    if (_renderLocation == FMCGSurfaceRenderLocationTexture) {
        
        CIImage *ret = [CIImage imageWithTexture:_FBOTextureId size:_size flipped:NO colorSpace:_colorSpace];
        assert(ret);
        return ret;
    }
    
    if (_renderLocation == FMCGSurfaceRenderLocationIOSurface) {
        
        if (NO) { // 10.8 workaround for speed issues.  Yes, really.
            
            if (!_cvPixelBuffer) {
                CVReturn r = CVPixelBufferCreateWithIOSurface(Nil, _ioSurface, nil, &_cvPixelBuffer);
                assert(r == kCVReturnSuccess);
            }
            
            CIImage *ret = [CIImage imageWithCVImageBuffer:_cvPixelBuffer options:@{(id)kCIContextOutputColorSpace: (__bridge id)_colorSpace}];
            
            return ret;
        }
        
        return [CIImage imageWithIOSurface:_ioSurface options:@{(id)kCIContextOutputColorSpace: (__bridge id)_colorSpace}];
    }
    
    assert(_renderLocation == FMCGSurfaceRenderLocationCPU);
    
    CGImageRef r = [self createCGImageWithNoFaults];
    CIImage *c = [CIImage imageWithCGImage:r];
    CGImageRelease(r);
    return c;
}

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r {
    
    im = [im imageByCroppingToRect:NSIntegralRectWithOptions(r, NSAlignAllEdgesOutward)];
    
    
    if (_renderLocation == FMCGSurfaceRenderLocationTexture) {
        [self setFBO];
        
        // Bind FBO
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _FBOid);
        
        // set GL state
        GLint width = (GLint)ceil(_size.width);
        GLint height = (GLint)ceil(_size.height);
        
        // the next few calls simply map an orthographic
        // projection or screen aligned 2D area for Core Image to
        // draw into
        {
            glViewport(0, 0, width, height);
            
            //glViewport(r.origin.x, r.origin.y, r.size.width, r.size.height);
            
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glOrtho(0, width, 0, height, -1, 1);
            
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
        }
        
        assert(_context);
        
        [_context drawImage:im inRect:r fromRect:r];
        
        // Bind to default framebuffer (unbind FBO)
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
        
    }
    else if (_renderLocation == FMCGSurfaceRenderLocationIOSurface) {
        uint32_t ioLockSeed;
        IOSurfaceLock(_ioSurface, 0, &ioLockSeed);
        
        // CGLTexImageIOSurface2D
        
        [_context render:im toIOSurface:_ioSurface bounds:[self extent] colorSpace:_colorSpace];
        //[_context render:im toBitmap:IOSurfaceGetBaseAddress(_ioSurface) rowBytes:IOSurfaceGetBytesPerRow(_ioSurface) bounds:[self extent] format:kCIFormatARGB8 colorSpace:_colorSpace];
        
        IOSurfaceUnlock(_ioSurface, 0, &ioLockSeed);
    }
    else {
        [_context drawImage:im inRect:r fromRect:r];
    }
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
    return CGRectMake(0, 0, _size.width, _size.height);
}







// Create or update the hardware accelerated offscreen area
// Framebuffer object aka. FBO
- (void)setFBO {
    
    if (_hasSetupFBO) {
        return;
    }
    
    _hasSetupFBO = YES;
    
    // If not previously setup
    // generate IDs for FBO and its associated texture
    if (!_FBOid)
    {
        // Make sure the framebuffer extenstion is supported
        const GLubyte* strExt;
        GLboolean isFBO;
        // Get the extenstion name string.
        // It is a space-delimited list of the OpenGL extenstions
        // that are supported by the current renderer
        strExt = glGetString(GL_EXTENSIONS);
        isFBO = gluCheckExtension((const GLubyte*)"GL_EXT_framebuffer_object", strExt);
        if (!isFBO)
        {
            NSLog(@"Your system does not support framebuffer extension");
        }
        
        // create FBO object
        glGenFramebuffersEXT(1, &_FBOid);
        // the texture
        glGenTextures(1, &_FBOTextureId);
    }
    
    // Bind to FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _FBOid);
    
    // Sanity check against maximum OpenGL texture size
    // If bigger adjust to maximum possible size
    // while maintain the aspect ratio
    GLint maxTexSize;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexSize);
    if (_size.width > maxTexSize || _size.height > maxTexSize) {
        assert(NO);
    }
    
    // Initialize FBO Texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _FBOTextureId);
    
    // Using GL_LINEAR because we want a linear sampling for this particular case
    // if your intention is to simply get the bitmap data out of Core Image
    // you might want to use a 1:1 rendering and GL_NEAREST
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // the GPUs like the GL_BGRA / GL_UNSIGNED_INT_8_8_8_8_REV combination
    // others are also valid, but might incur a costly software translation.
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA, _size.width, _size.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    
    // and attach texture to the FBO as its color destination
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _FBOTextureId, 0);
    
    // NOTE: for this particular case we don't need a depth buffer when drawing to the FBO,
    // if you do need it, make sure you add the depth size in the pixel format, and
    // you might want to do something along the lines of:
#if 0
    // Initialize Depth Render Buffer
    GLuint depth_rb;
    glGenRenderbuffersEXT(1, &depth_rb);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, depth_rb);
    glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT, _size.width, _size.height);
    // and attach it to the FBO
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, depth_rb);
#endif
    
    // Make sure the FBO was created succesfully.
    if (GL_FRAMEBUFFER_COMPLETE_EXT != glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT)) {
        NSLog(@"Framebuffer Object creation or update failed!");
    }
    
    // unbind FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
}

@end

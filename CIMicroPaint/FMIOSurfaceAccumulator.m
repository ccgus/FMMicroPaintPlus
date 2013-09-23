
#import "FMIOSurfaceAccumulator.h"
#import <QuartzCore/QuartzCore.h>
#import <GLUT/glut.h>

SInt32 FMSystemVersion(void);

@interface FMIOSurfaceAccumulator ()

@property (assign) IOSurfaceRef ioSurface;

@property (strong) CIContext *context;
@property (strong) CIImage *lastImage;
@property (assign) CGColorSpaceRef colorSpace;

@property (assign) CGLContextObj cglContext;
@property (assign) CGLPixelFormatObj cglPixelFormat;

@property (assign) BOOL hasSetupFBO;
@property (assign) GLuint FBOid;
@property (assign) GLuint FBOTextureId;
@property (assign) NSSize size;
@property (assign) CVPixelBufferRef cvPixelBuffer;
@end

@implementation FMIOSurfaceAccumulator


+ (id)accumulatorWithSize:(NSSize)s CGLContext:(CGLContextObj)cglCtx pixelFormat:(CGLPixelFormatObj)pf colorSpace:(CGColorSpaceRef)colorSpace {
    
    FMIOSurfaceAccumulator *surf = [FMIOSurfaceAccumulator new];
    
    [surf setColorSpace:CGColorSpaceRetain(colorSpace)];
    [surf setCglContext:cglCtx];
    [surf setCglPixelFormat:pf];
    
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
    
    if (_FBOTextureId) {
        glDeleteTextures(1, &_FBOTextureId);
    }
    
	if (_FBOid) {
        glDeleteFramebuffersEXT(1, &_FBOid);
    }
    
    
}

- (void)checkErr:(int)step {
    GLenum error = glGetError();
    if(error != GL_NO_ERROR) {
        NSLog(@"%d error = %d", step, error);
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
                            (id)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
                            };
    
    assert(!_ioSurface);
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)opts);
    
    _context = [CIContext contextWithCGLContext:_cglContext pixelFormat:_cglPixelFormat colorSpace:_colorSpace options:@{(id)kCIContextOutputColorSpace: (__bridge id)_colorSpace, kCIContextWorkingColorSpace: (__bridge id)_colorSpace}];
    
}


- (CIImage*)image {
    
    if (_lastImage) {
        return _lastImage;
    }
    
    CIImage *returnImage = nil;
    
    if (FMSystemVersion() < 0x1090) { // 10.8 workaround for speed issues.  Yes, really.
        
        if (!_cvPixelBuffer) {
            CVReturn r = CVPixelBufferCreateWithIOSurface(Nil, _ioSurface, nil, &_cvPixelBuffer);
            assert(r == kCVReturnSuccess);
        }
        
        returnImage = [CIImage imageWithCVImageBuffer:_cvPixelBuffer options:@{(id)kCIContextOutputColorSpace: (__bridge id)_colorSpace}];
        
    }
    else {
        returnImage = [CIImage imageWithIOSurface:_ioSurface options:@{(id)kCIContextOutputColorSpace: (__bridge id)_colorSpace}];
    }
    
    // drawing to a texture is upside down, so we need to fix that here.
    returnImage = [returnImage imageByApplyingTransform:CGAffineTransformMakeScale(1, -1)];
    returnImage = [returnImage imageByApplyingTransform:CGAffineTransformMakeTranslation(0, _size.height)];
    
    _lastImage = returnImage;
    
    return returnImage;
}

- (void)setImage:(CIImage *)im dirtyRect:(CGRect)r {
    
    _lastImage = nil;
    
#if 1
    
    [self setFBO];
    
    // Bind FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _FBOid);
    
    // set GL state
    GLint width = (GLint)ceil(_size.width);
    GLint height = (GLint)ceil(_size.height);
    
    // the next few calls simply map an orthographic
    // projection or screen aligned 2D area for Core Image to
    // draw into
    glViewport(0, 0, width, height);
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, width, 0, height, -1, 1);
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
    glScissor(r.origin.x, r.origin.y, r.size.width, r.size.height);
    glEnable(GL_SCISSOR_TEST);
    
    assert(_context);
    [_context drawImage:im inRect:r fromRect:r];
    
    glDisable(GL_SCISSOR_TEST);
    
    // Bind to default framebuffer (unbind FBO)
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);

#else
    // this is SLOOOOOOOOOOOW because it draws the whole dang image.
    [_context render:im toIOSurface:_ioSurface bounds:[self extent] colorSpace:_colorSpace];
#endif
    
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
    if (!_FBOid) {
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
    
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    
    // Initialize FBO Texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _FBOTextureId);
    
    // if your intention is to simply get the bitmap data out of Core Image
    // you might want to use a 1:1 rendering and GL_NEAREST
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // the GPUs like the GL_BGRA / GL_UNSIGNED_INT_8_8_8_8_REV combination
    // others are also valid, but might incur a costly software translation.
    
    // Since we're drawing to an IOSurface, we'll replace glTexImage2D with CGLTexImageIOSurface2D.
    // glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA, _size.width, _size.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    
    assert([self cglContext]);
    CGLError err = CGLTexImageIOSurface2D([self cglContext], GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, (GLsizei)IOSurfaceGetWidth(_ioSurface), (GLsizei)IOSurfaceGetHeight(_ioSurface), GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _ioSurface, 0);
    
    assert(!err);
    
    // and attach texture to the FBO as its color destination
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _FBOTextureId, 0);
    
    // Make sure the FBO was created succesfully.
    if (GL_FRAMEBUFFER_COMPLETE_EXT != glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT)) {
        NSLog(@"Framebuffer Object creation or update failed!");
    }
    
    // unbind FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
}

@end

SInt32 FMSystemVersion(void) {
    
    static dispatch_once_t once;
    static int FMSystemVersionVal = 0x00;
    
    dispatch_once(&once, ^{
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        
        NSString *prodVersion = [d objectForKey:@"ProductVersion"];
        
        // sanity.
        assert([prodVersion isKindOfClass:[NSString class]]);
        
        if ([[prodVersion componentsSeparatedByString:@"."] count] < 3) {
            prodVersion = [prodVersion stringByAppendingString:@".0"];
        }
        
        assert([[prodVersion componentsSeparatedByString:@"."] count] == 3);
        
        NSString *junk = [prodVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
        
        
        char *e = nil;
        FMSystemVersionVal = (int) strtoul([junk UTF8String], &e, 16);
        
    });
    
    return FMSystemVersionVal;
}





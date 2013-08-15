#import <Cocoa/Cocoa.h>
#import <QuartzCore/CoreImage.h>

@interface FMCIView : NSOpenGLView {
    
    NSRect				_lastBounds;
	CGLContextObj		_cglContext;
	NSOpenGLPixelFormat *pixelFormat;
	CGDirectDisplayID	_directDisplayID;
}

@property (assign) IBOutlet NSTextField *scaleField;

- (void)setContextOptions:(NSDictionary *)dict;

@end


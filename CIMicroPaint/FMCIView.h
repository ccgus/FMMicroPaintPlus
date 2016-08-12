#import <Cocoa/Cocoa.h>
#import <QuartzCore/CoreImage.h>
#import <MetalKit/MetalKit.h>

@interface FMCIView : MTKView {
    
    NSRect				_lastBounds;
    
	CGDirectDisplayID	_directDisplayID;
}

@property (assign) IBOutlet NSTextField *scaleField;

- (void)setContextOptions:(NSDictionary *)dict;

@end


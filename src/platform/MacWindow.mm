#import "MacWindow.h"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

// ---------------------------------------------------------------------------
// AppDelegate — quit when last window is closed
// ---------------------------------------------------------------------------
@interface KisekiAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation KisekiAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

// ---------------------------------------------------------------------------
// A minimal NSView subclass backed by CAMetalLayer
// ---------------------------------------------------------------------------
@interface MetalView : NSView
@property (nonatomic, strong) CAMetalLayer* metalLayer;
@end

@implementation MetalView

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        _metalLayer = [CAMetalLayer layer];
        _metalLayer.device = device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.framebufferOnly = YES;
        _metalLayer.drawableSize = frame.size;
        self.layer = _metalLayer;
    }
    return self;
}

- (CALayer*)makeBackingLayer {
    return _metalLayer ? _metalLayer : [super makeBackingLayer];
}

@end

// ---------------------------------------------------------------------------
// MacWindow implementation
// ---------------------------------------------------------------------------
MacWindow::MacWindow(int width, int height, const char* title)
    : m_width(width), m_height(height), m_window(nullptr), m_metalLayer(nullptr)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    KisekiAppDelegate* delegate = [[KisekiAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

    NSRect frame = NSMakeRect(100, 100, width, height);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable;

    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    if (!window) {
        NSLog(@"[KisekiEngine] Failed to create NSWindow");
        return;
    }

    [window setTitle:[NSString stringWithUTF8String:title]];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[KisekiEngine] Failed to create Metal device");
        return;
    }

    MetalView* metalView = [[MetalView alloc] initWithFrame:frame device:device];
    [window setContentView:metalView];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    m_window = (__bridge_retained void*)window;
    m_metalLayer = (__bridge void*)metalView.metalLayer;
}

MacWindow::~MacWindow() {
    if (m_window) {
        NSWindow* window = (__bridge_transfer NSWindow*)m_window;
        [window close];
        m_window = nullptr;
    }
}

void* MacWindow::getMetalLayer() const {
    return m_metalLayer;
}

bool MacWindow::pollEvents() {
    @autoreleasepool {
        while (true) {
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:nil
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (!event) break;
            [NSApp sendEvent:event];
            [NSApp updateWindows];
        }
    }

    if (m_window) {
        NSWindow* window = (__bridge NSWindow*)m_window;
        return [window isVisible];
    }
    return false;
}

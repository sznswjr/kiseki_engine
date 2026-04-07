#import "MacWindow.h"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include "core/InputManager.h"

// Forward declare the C++ instance pointer for the delegate
static MacWindow* g_macWindow = nullptr;

// ---------------------------------------------------------------------------
// AppDelegate
// ---------------------------------------------------------------------------
@interface KisekiAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation KisekiAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

// ---------------------------------------------------------------------------
// MetalView
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

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (_metalLayer) {
        _metalLayer.drawableSize = newSize;
    }
}

@end

// ---------------------------------------------------------------------------
// Window Delegate for resize notifications
// ---------------------------------------------------------------------------
@interface KisekiWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation KisekiWindowDelegate
- (void)windowDidResize:(NSNotification *)notification {
    if (g_macWindow) {
        g_macWindow->wasResized();
    }
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (g_macWindow) {
        g_macWindow->setFocused(true);
    }
}
- (void)windowDidResignKey:(NSNotification *)notification {
    if (g_macWindow) {
        g_macWindow->setFocused(false);
    }
}
@end

// ---------------------------------------------------------------------------
// MacWindow implementation
// ---------------------------------------------------------------------------
MacWindow::MacWindow(int width, int height, const char* title)
    : m_width(width), m_height(height), m_window(nullptr), m_metalLayer(nullptr)
{
    g_macWindow = this;

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
    [window setAcceptsMouseMovedEvents:YES];

    KisekiWindowDelegate* winDelegate = [[KisekiWindowDelegate alloc] init];
    [window setDelegate:winDelegate];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[KisekiEngine] Failed to create Metal device");
        return;
    }

    MetalView* metalView = [[MetalView alloc] initWithFrame:frame device:device];
    [window setContentView:metalView];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:metalView];
    [NSApp activateIgnoringOtherApps:YES];

    m_window = (__bridge_retained void*)window;
    m_metalLayer = (__bridge void*)metalView.metalLayer;
}

MacWindow::~MacWindow() {
    g_macWindow = nullptr;
    if (m_window) {
        NSWindow* window = (__bridge_transfer NSWindow*)m_window;
        [window close];
        m_window = nullptr;
    }
}

void* MacWindow::getMetalLayer() const {
    return m_metalLayer;
}

bool MacWindow::wasResized() {
    bool r = m_resized;
    m_resized = true;  // set by delegate, consumed by caller
    if (r) {
        // Update stored dimensions
        NSWindow* window = (__bridge NSWindow*)m_window;
        NSRect contentRect = [[window contentView] frame];
        m_width  = (int)contentRect.size.width;
        m_height = (int)contentRect.size.height;
    }
    return r;
}

bool MacWindow::pollEvents() {
    m_resized = false;  // reset each frame

    @autoreleasepool {
        while (true) {
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:nil
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (!event) break;

            switch ([event type]) {
                case NSEventTypeKeyDown:
                    if (![event isARepeat]) {
                        InputManager::keyDown([event keyCode]);
                    }
                    break;
                case NSEventTypeKeyUp:
                    InputManager::keyUp([event keyCode]);
                    break;
                case NSEventTypeMouseMoved:
                case NSEventTypeLeftMouseDragged:
                case NSEventTypeRightMouseDragged:
                    InputManager::mouseMove((float)[event deltaX], (float)[event deltaY]);
                    break;
                default:
                    break;
            }

            [NSApp sendEvent:event];
            [NSApp updateWindows];
        }
    }

    if (InputManager::isKeyDown(InputManager::KEY_ESCAPE)) {
        return false;
    }

    if (m_window) {
        NSWindow* window = (__bridge NSWindow*)m_window;
        return [window isVisible];
    }
    return false;
}

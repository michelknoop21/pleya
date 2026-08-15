// Makes one engine-internal method visible to Swift.
//
// The tvOS fork engine swizzles `-[UIApplication sendEvent:]` and
// `-[UIWindow sendEvent:]`, and on every press it asks
// `-[FlutterViewController tvosHandlePressFromUIEvent:]` whether it may claim
// the event. YES skips the original `sendEvent:` entirely, so UIKit never
// starts its responder chain. The engine's own implementation ends in
// `synthesizeRemotePressType:`, which returns YES unconditionally: that is why
// a click on the tvOS system keyboard entered nothing.
//
// The method is not declared in any public Flutter header, so Swift cannot see
// it and `PleyaFlutterViewController` cannot override it. This category is a
// promise to the compiler, not an implementation: the engine still provides the
// body, and `super` reaches it.
//
// The engine is pinned (see `tvos/engine.version`). `AppDelegate` logs once at
// startup whether `FlutterViewController` still responds to this selector, so a
// bump that drops or renames it surfaces as a log line instead of a keyboard
// that silently ignores every click again.

#import <Flutter/Flutter.h>

@interface FlutterViewController (PleyaTvosPress)
- (BOOL)tvosHandlePressFromUIEvent:(UIPress*)press;
@end

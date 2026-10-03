/// The web half of [WindowFocus]: there is no second instance to raise.
///
/// `window_focus.dart` already documents both calls as no-ops returning false
/// everywhere except Windows, so the browser gets the answer callers were
/// written against. Single-instance hand-off does not exist on the web either
/// — a tab is not a process holding a lock on a container — so nothing
/// upstream of here has a case to learn.
library;

bool platformAllowForegroundHandover() => false;

bool platformRaiseSelf() => false;

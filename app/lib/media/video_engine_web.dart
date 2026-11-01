/// The web half of [VideoEngine]: there is no engine to install or load.
///
/// The split engine exists because mpv and ANGLE are 60 MB that most students
/// never need, so a desktop build downloads them on demand. A browser already
/// has a video decoder — the one in the browser — so the question this class
/// answers does not arise, and the honest answer to "is the engine loaded" is
/// no.
///
/// [platformCanLoadEngine] is a `const false` rather than a runtime answer so
/// that [VideoEngine.load] can return before touching anything: the rest of
/// that class is `Directory`, `File` and `Process`, which compile on the web
/// and throw when called.
library;

const bool platformCanLoadEngine = false;

bool platformLoadEngineLibraries(String dir, List<String> names) => false;

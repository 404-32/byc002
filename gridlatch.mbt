// GridLatch is organized into model, topology, inference, JSON I/O, and
// restoration-verification modules. The package root intentionally contains no
// executable entry point so it can be embedded in native tools or WebAssembly.

///|
/// Public package version. Keep this synchronized with `moon.mod`.
pub fn version() -> String {
  "0.1.0"
}

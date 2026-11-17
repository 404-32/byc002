// GridDiagnose keeps the original GridLatch outage engine in model, topology,
// inference, JSON I/O, and restoration-verification modules. New multi-model
// diagnostics share the same package so the core can be embedded in Native or
// WebAssembly applications.

///|
/// Public package version. Keep this synchronized with `moon.mod`.
pub fn version() -> String {
  "0.3.0"
}

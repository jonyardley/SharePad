// Pure: should this frame be drawn to the thumbnail, given the last drawn one? No
// AVFoundation, so it's unit-testable without hardware (DESIGN.md §11). Seconds come
// from the sample buffer's presentation timestamp upstream.
func shouldRenderFrame(currentSeconds: Double, lastRenderedSeconds: Double?,
                       minInterval: Double) -> Bool {
    guard let last = lastRenderedSeconds else { return true }
    let elapsed = currentSeconds - last
    // A backwards timestamp means the timeline reset (e.g. a device switch) — draw now.
    return elapsed < 0 || elapsed >= minInterval
}

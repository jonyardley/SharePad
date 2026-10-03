public extension StreamSender {
    struct Stats: Sendable {
        public var framesPerSecond: Double = 0
        public var kilobitsPerSecond: Double = 0
        public var encodedFrames = 0
        public var skippedFrames = 0
        public var keyframes = 0
        public var interface = ""
        public var encodeMilliseconds: Double = 0
    }
}

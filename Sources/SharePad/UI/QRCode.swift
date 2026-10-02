import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCode {
    private static let context = CIContext()

    static func image(for text: String, moduleSize: CGFloat = 8) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

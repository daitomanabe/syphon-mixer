import Foundation

public enum ScaleMode: String, CaseIterable, Sendable {
    case fillCrop = "Fill / Crop"
    case fit = "Fit"
    case stretch = "Stretch"
}

public struct MixerSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var isValid: Bool {
        width > 0.0 && height > 0.0
    }
}

public struct UnitRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = UnitRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
}

public struct TextureMapping: Equatable, Sendable {
    public var destination: UnitRect
    public var uv: UnitRect

    public init(destination: UnitRect, uv: UnitRect) {
        self.destination = destination
        self.uv = uv
    }
}

public enum AspectLayout {
    public static func mapping(source: MixerSize, output: MixerSize, mode: ScaleMode) -> TextureMapping {
        guard source.isValid && output.isValid else {
            return TextureMapping(destination: .full, uv: .full)
        }

        let sourceAspect = source.width / source.height
        let outputAspect = output.width / output.height

        switch mode {
        case .stretch:
            return TextureMapping(destination: .full, uv: .full)

        case .fit:
            if sourceAspect > outputAspect {
                let height = outputAspect / sourceAspect
                return TextureMapping(
                    destination: UnitRect(x: 0.0, y: (1.0 - height) * 0.5, width: 1.0, height: height),
                    uv: .full
                )
            }

            let width = sourceAspect / outputAspect
            return TextureMapping(
                destination: UnitRect(x: (1.0 - width) * 0.5, y: 0.0, width: width, height: 1.0),
                uv: .full
            )

        case .fillCrop:
            if sourceAspect > outputAspect {
                let width = outputAspect / sourceAspect
                return TextureMapping(
                    destination: .full,
                    uv: UnitRect(x: (1.0 - width) * 0.5, y: 0.0, width: width, height: 1.0)
                )
            }

            let height = sourceAspect / outputAspect
            return TextureMapping(
                destination: .full,
                uv: UnitRect(x: 0.0, y: (1.0 - height) * 0.5, width: 1.0, height: height)
            )
        }
    }
}

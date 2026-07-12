import AppKit
import CoreGraphics

// MARK: - Custom pet image loading (assets/pet.png fallback path)

func loadPetImage() -> NSImage? {
    let fileManager = FileManager.default
    let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let parent = executable.deletingLastPathComponent()
    let resources = Bundle.main.resourceURL

    let names = ["pet.png", "pet.jpg", "pet.jpeg"]
    var folders = [
        current,
        current.appendingPathComponent("assets"),
        executable,
        executable.appendingPathComponent("assets"),
        parent.appendingPathComponent("assets")
    ]

    if let resources {
        folders.append(resources)
        folders.append(resources.appendingPathComponent("assets"))
    }

    for folder in folders {
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else {
                continue
            }
            return imageByRemovingWhiteBackground(image) ?? image
        }
    }

    return nil
}

func imageByRemovingWhiteBackground(_ image: NSImage) -> NSImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    // Draw inside withUnsafeMutableBytes so the buffer pointer stays valid
    // for the whole lifetime of the CGContext (passing &pixels directly is
    // undefined behavior: the pointer is only guaranteed for the call).
    let drewSuccessfully = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress,
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
              )
        else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drewSuccessfully else { return nil }

    func pixelOffset(_ x: Int, _ y: Int) -> Int {
        y * bytesPerRow + x * bytesPerPixel
    }

    func isBackgroundCandidate(_ offset: Int) -> Bool {
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let alpha = Int(pixels[offset + 3])
        let brightest = max(red, green, blue)
        let darkest = min(red, green, blue)
        let colorSpread = brightest - darkest

        if alpha < 8 {
            return true
        }

        return (darkest >= 228 && colorSpread <= 42) || darkest >= 246
    }

    var isBackground = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    queue.reserveCapacity(width * height / 4)

    func enqueueBackground(_ x: Int, _ y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }

        let position = y * width + x
        guard !isBackground[position] else { return }
        guard isBackgroundCandidate(pixelOffset(x, y)) else { return }

        isBackground[position] = true
        queue.append(position)
    }

    for x in 0..<width {
        enqueueBackground(x, 0)
        enqueueBackground(x, height - 1)
    }

    for y in 0..<height {
        enqueueBackground(0, y)
        enqueueBackground(width - 1, y)
    }

    var cursor = 0
    while cursor < queue.count {
        let position = queue[cursor]
        cursor += 1

        let x = position % width
        let y = position / width
        enqueueBackground(x + 1, y)
        enqueueBackground(x - 1, y)
        enqueueBackground(x, y + 1)
        enqueueBackground(x, y - 1)
    }

    var visitedCandidate = [Bool](repeating: false, count: width * height)
    let largeInteriorArea = max(180, (width * height) / 1300)
    let largeInteriorWidth = max(18, width / 24)
    let largeInteriorHeight = max(20, height / 24)

    func markLargeInteriorWhiteComponents() {
        for start in 0..<(width * height) {
            guard !isBackground[start], !visitedCandidate[start] else { continue }

            let startX = start % width
            let startY = start / width
            guard isBackgroundCandidate(pixelOffset(startX, startY)) else {
                visitedCandidate[start] = true
                continue
            }

            var component: [Int] = []
            var componentQueue = [start]
            var componentCursor = 0
            var minX = startX
            var maxX = startX
            var minY = startY
            var maxY = startY
            visitedCandidate[start] = true

            while componentCursor < componentQueue.count {
                let position = componentQueue[componentCursor]
                componentCursor += 1
                component.append(position)

                let x = position % width
                let y = position / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                let neighbors = [
                    (x + 1, y),
                    (x - 1, y),
                    (x, y + 1),
                    (x, y - 1)
                ]

                for (neighborX, neighborY) in neighbors {
                    guard neighborX >= 0, neighborX < width, neighborY >= 0, neighborY < height else {
                        continue
                    }

                    let neighborPosition = neighborY * width + neighborX
                    guard !isBackground[neighborPosition], !visitedCandidate[neighborPosition] else {
                        continue
                    }

                    visitedCandidate[neighborPosition] = true
                    guard isBackgroundCandidate(pixelOffset(neighborX, neighborY)) else {
                        continue
                    }

                    componentQueue.append(neighborPosition)
                }
            }

            let componentWidth = maxX - minX + 1
            let componentHeight = maxY - minY + 1
            let isLargeInteriorBackground = component.count >= largeInteriorArea
                || componentWidth >= largeInteriorWidth
                || componentHeight >= largeInteriorHeight

            if isLargeInteriorBackground {
                for position in component {
                    isBackground[position] = true
                }
            }
        }
    }

    markLargeInteriorWhiteComponents()

    func hasBackgroundNeighbor(_ x: Int, _ y: Int, radius: Int) -> Bool {
        for neighborY in max(0, y - radius)...min(height - 1, y + radius) {
            for neighborX in max(0, x - radius)...min(width - 1, x + radius) {
                if isBackground[neighborY * width + neighborX] {
                    return true
                }
            }
        }
        return false
    }

    func scalePixelAlpha(at offset: Int, by factor: CGFloat) {
        let bounded = min(1, max(0, factor))
        pixels[offset] = UInt8(CGFloat(pixels[offset]) * bounded)
        pixels[offset + 1] = UInt8(CGFloat(pixels[offset + 1]) * bounded)
        pixels[offset + 2] = UInt8(CGFloat(pixels[offset + 2]) * bounded)
        pixels[offset + 3] = UInt8(CGFloat(pixels[offset + 3]) * bounded)
    }

    for y in 0..<height {
        for x in 0..<width {
            let position = y * width + x
            let offset = pixelOffset(x, y)

            if isBackground[position] {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                continue
            }

            guard hasBackgroundNeighbor(x, y, radius: 2) else { continue }

            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let brightest = max(red, green, blue)
            let darkest = min(red, green, blue)
            let colorSpread = brightest - darkest

            if darkest > 172 && colorSpread < 52 {
                let keep = CGFloat(245 - darkest) / 73
                scalePixelAlpha(at: offset, by: keep)
            }
        }
    }

    let data = Data(pixels)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let output = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        return nil
    }

    return NSImage(cgImage: output, size: image.size)
}

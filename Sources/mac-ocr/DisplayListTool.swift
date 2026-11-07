import Foundation
import CoreGraphics

func activeDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    ids = ids.filter { CGDisplayIsInMirrorSet($0) == 0 || CGDisplayIsMain($0) != 0 }
    ids.sort { CGDisplayIsMain($0) != 0 && CGDisplayIsMain($1) == 0 }
    return ids
}

func activeDisplayInfos() -> [DisplayInfo] {
    activeDisplayIDs().enumerated().map { offset, id in
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        return DisplayInfo(index: offset + 1, displayID: id, main: CGDisplayIsMain(id) != 0, x: bounds.origin.x, y: bounds.origin.y,
            width: bounds.width, height: bounds.height, pixelWidth: mode.map { $0.pixelWidth } ?? 0,
            pixelHeight: mode.map { $0.pixelHeight } ?? 0,
            scaleX: mode.map { CGFloat($0.pixelWidth) / max(bounds.width, 1) } ?? 1,
            scaleY: mode.map { CGFloat($0.pixelHeight) / max(bounds.height, 1) } ?? 1)
    }
}

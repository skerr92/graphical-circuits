import AppKit
import CoreText

extension BoardText {
    /// Convert the same glyph outlines to paths for the canvas and SVG, with KiCad's anchor semantics.
    /// The default font is a system substitute; positions, justification, width/height, and rotation come from the PCB.
    func vectorGraphic() -> BoardGraphic {
        let face = fontFace == nil || fontFace == "KiCad Font" ? "Helvetica" : fontFace!
        let initial = CTFontCreateWithName(face as CFString,max(1,size),nil)
        var font = CTFontCreateCopyWithAttributes(initial,max(1,size)*size/max(0.01,CTFontGetCapHeight(initial)),nil,nil)
        var traits: CTFontSymbolicTraits = []
        if bold == true { traits.insert(.traitBold) }
        if italic == true { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font,0,nil,traits,traits) { font = styled }
        let xScale = (fontWidth ?? size)/max(size,0.001)
        let lines = text.components(separatedBy:"\n")
        var contours: [[Point]] = []
        let advance = size*1.5
        for (lineIndex,lineText) in lines.enumerated() {
            let attributed = NSAttributedString(string:lineText,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font])
            let line = CTLineCreateWithAttributedString(attributed)
            var row: [[Point]] = []
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating:0,count:count), positions = [CGPoint](repeating:.zero,count:count)
                CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs)
                CTRunGetPositions(run,CFRange(location:0,length:0),&positions)
                for i in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(font,glyphs[i],nil) else { continue }
                    var current: [Point] = [], previous = CGPoint.zero
                    func point(_ p: CGPoint) -> Point { Point(x:(p.x+positions[i].x)*xScale,y:-(p.y+positions[i].y)) }
                    path.applyWithBlock { elementPointer in
                        let e = elementPointer.pointee
                        switch e.type {
                        case .moveToPoint:
                            if !current.isEmpty { row.append(current) }; current = [point(e.points[0])]; previous = e.points[0]
                        case .addLineToPoint: current.append(point(e.points[0])); previous = e.points[0]
                        case .addQuadCurveToPoint:
                            let a = previous, b = e.points[0], c = e.points[1]
                            for j in 1...12 { let t = Double(j)/12, u = 1-t; current.append(point(CGPoint(x:u*u*a.x+2*u*t*b.x+t*t*c.x,y:u*u*a.y+2*u*t*b.y+t*t*c.y))) }; previous = c
                        case .addCurveToPoint:
                            let a = previous, b = e.points[0], c = e.points[1], d = e.points[2]
                            for j in 1...16 { let t = Double(j)/16, u = 1-t; current.append(point(CGPoint(x:u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,y:u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y))) }; previous = d
                        case .closeSubpath: if !current.isEmpty { row.append(current) }; current = []
                        @unknown default: break
                        }
                    }
                    if !current.isEmpty { row.append(current) }
                }
            }
            let points = row.flatMap { $0 }
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
            let dx = horizontal == "left" ? -minX : horizontal == "right" ? -maxX : -(minX+maxX)/2
            contours += row.map { $0.map { Point(x:$0.x+dx,y:$0.y+Double(lineIndex)*advance) } }
        }
        let all = contours.flatMap { $0 }
        let minY = all.map(\.y).min() ?? 0, maxY = all.map(\.y).max() ?? 0
        let dy = vertical == "top" ? -minY : vertical == "bottom" ? -maxY : -(minY+maxY)/2
        let a = angle * .pi/180
        contours = contours.map { $0.map { p in
            let x = mirrored == true ? -p.x : p.x, y = p.y+dy
            return Point(x:point.x+x*cos(a)+y*sin(a),y:point.y-x*sin(a)+y*cos(a))
        } }
        return BoardGraphic(contours:contours,fill:"#f0eee2",feature:"silkscreen-text")
    }
}

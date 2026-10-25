import AppKit
import UniformTypeIdentifiers

@MainActor final class Canvas: NSView {
    var diagram = Diagram()
    var selected: UUID?
    var selectedWire: Int?
    var draggingWire = false
    var wireDragOffset = Point(x:0,y:0)
    var pending: Endpoint?
    var wiring = false
    var wireColor = "#dc654c"
    var history: [Diagram] = []
    var redoHistory: [Diagram] = []
    var dragStart: NSPoint?
    var original: Point?
    var status: ((String) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    func checkpoint() { history.append(diagram); redoHistory = [] }
    func undoEdit() { guard let d = history.popLast() else { return }; redoHistory.append(diagram); diagram = d; pending = nil; selectedWire = nil; selected = nil; needsDisplay = true }
    func redoEdit() { guard let d = redoHistory.popLast() else { return }; history.append(diagram); diagram = d; selectedWire = nil; selected = nil; pending = nil; needsDisplay = true }
    func editSelectedPart(label: String, ledColor: LEDColor?) {
        guard let i = diagram.parts.firstIndex(where: { $0.id == selected }) else { return }
        let text = label.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard diagram.parts[i].label != text || (diagram.parts[i].kind == "LED" && diagram.parts[i].ledColor != ledColor) else { return }
        checkpoint()
        diagram.parts[i].label = text
        if diagram.parts[i].kind == "LED" { diagram.parts[i].ledColor = ledColor }
        needsDisplay = true
    }
    func drawGraphic(_ graphic: BoardGraphic, offset: Point) {
        let path = NSBezierPath(); path.windingRule = .evenOdd
        for points in graphic.contours {
            guard let first = points.first else { continue }
            path.move(to:NSPoint(x:offset.x+first.x,y:offset.y+first.y))
            for p in points.dropFirst() { path.line(to:NSPoint(x:offset.x+p.x,y:offset.y+p.y)) }
            if graphic.closed { path.close() }
        }
        if let fill = graphic.fill { NSColor(hex:fill).setFill(); path.fill() }
        if let stroke = graphic.stroke { NSColor(hex:stroke).setStroke(); path.lineWidth = graphic.lineWidth; path.lineJoinStyle = .round; path.stroke() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: "#faf9f6").setFill(); bounds.fill()
        NSColor(hex: "#dedfd9").setFill()
        for x in stride(from: 0, to: Int(bounds.width), by: CanvasGrid.spacing) { for y in stride(from: 0, to: Int(bounds.height), by: CanvasGrid.spacing) { NSRect(x: Double(x), y: Double(y), width: 1.5, height: 1.5).fill() } }
        for p in diagram.parts {
            let rect = NSRect(x: p.position.x, y: p.position.y, width: p.width, height: p.height)
            if let board = p.boardDrawing {
                drawGraphic(board.substrate,offset:p.position)
                for graphic in board.graphics { drawGraphic(graphic,offset:p.position) }
                for text in board.texts { drawGraphic(text.vectorGraphic(),offset:p.position) }
            }
            for art in p.artwork {
                NSColor(hex:art.fill).setFill()
                let r = art.rect.offsetBy(dx:rect.minX,dy:rect.minY)
                (art.ellipse ? NSBezierPath(ovalIn:r) : NSBezierPath(roundedRect:r,xRadius:art.radius,yRadius:art.radius)).fill()
            }
            if p.id == selected { NSColor.systemBlue.setStroke(); let border = NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8); border.lineWidth = 2; border.stroke() }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: p.kind == "Board" && p.boardDrawing == nil ? NSColor.white : NSColor.darkGray]
            let size = (p.label as NSString).size(withAttributes: attrs)
            if p.boardDrawing == nil { (p.label as NSString).draw(at: NSPoint(x: rect.midX-size.width/2, y: (["LED","Resistor","Capacitor"].contains(p.kind) || p.boardDrawing != nil) ? rect.maxY+2 : rect.midY-8), withAttributes: attrs) }
            if p.kind == "Breadboard", p.pins.contains(where: { $0.name.hasPrefix("Top +") }) {
                for (text,y) in [("+",15.0),("−",32.0),("+",252.0),("−",269.0)] {
                    (text as NSString).draw(at:NSPoint(x:rect.minX+5,y:rect.minY+y),withAttributes:[.font:NSFont.boldSystemFont(ofSize:12),.foregroundColor:NSColor(hex:text == "+" ? "#d6534b" : "#4785b5")])
                }
            }
            for b in p.packages { NSColor(hex: "#303936").setFill(); NSBezierPath(roundedRect: NSRect(x: rect.minX+b.x,y: rect.minY+b.y,width: b.width,height: b.height),xRadius: 2,yRadius: 2).fill() }
            for (i, pin) in p.pins.enumerated() {
                let r = NSRect(x: rect.minX+pin.point.x-3, y: rect.minY+pin.point.y-3, width: 6, height: 6)
                if p.boardDrawing == nil {
                    NSColor(hex: "#c4ad70").setFill(); NSBezierPath(ovalIn: r).fill()
                    NSColor(hex: "#454b49").setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1.2, dy: 1.2)).fill()
                }
                if pending?.part == p.id && pending?.pin == i { NSColor.systemBlue.setStroke(); NSBezierPath(ovalIn: r.insetBy(dx: -4, dy: -4)).stroke() }
            }
        }
        for (index,wire) in diagram.wires.enumerated() {
            let points = diagram.route(wire)
            guard let first = points.first else { continue }
            let path = NSBezierPath(); path.move(to:NSPoint(x:first.x,y:first.y))
            for p in points.dropFirst() { path.line(to:NSPoint(x:p.x,y:p.y)) }
            path.lineWidth = 4; path.lineJoinStyle = .round; NSColor(hex:wire.color).setStroke(); path.stroke()
            if selectedWire == index {
                let bend = points[2]
                let handle = NSBezierPath(ovalIn:NSRect(x:bend.x-6,y:bend.y-6,width:12,height:12))
                NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); handle.lineWidth = 2; handle.stroke()
            }
        }
    }
    func hitWire(_ pt: NSPoint) -> Int? {
        for i in diagram.wires.indices.reversed() {
            let points = diagram.route(diagram.wires[i])
            for (a,b) in zip(points,points.dropFirst()) {
                let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
                let t = length == 0 ? 0 : max(0,min(1,((pt.x-a.x)*dx+(pt.y-a.y)*dy)/length))
                if hypot(pt.x-a.x-t*dx,pt.y-a.y-t*dy) <= 7 { return i }
            }
        }
        return nil
    }
    func nearestPin(to point: NSPoint) -> (endpoint: Endpoint, label: String)? {
        var best: (endpoint: Endpoint, label: String, distance: Double)?
        for part in diagram.parts.reversed() {
            for (i,pin) in part.pins.enumerated() {
                let distance = hypot(point.x-part.position.x-pin.point.x,point.y-part.position.y-pin.point.y)
                if distance <= 8, best == nil || distance < best!.distance {
                    best = (Endpoint(part:part.id,pin:i),"\(part.label) · \(pin.name)",distance)
                }
            }
        }
        return best.map { ($0.endpoint,$0.label) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        if wiring {
            if let target = nearestPin(to:pt) {
                let end = target.endpoint
                if let start = pending {
                    if start.part != end.part || start.pin != end.pin { checkpoint(); diagram.wires.append(Wire(from:start,to:end,color:wireColor)) }; pending = nil
                } else { pending = end }
                status?(target.label); needsDisplay = true; return
            }
            pending = nil
        } else {
            if let i = hitWire(pt) {
                checkpoint(); selectedWire = i; selected = nil; draggingWire = true
                let bend = diagram.route(diagram.wires[i])[2]
                wireDragOffset = Point(x:bend.x-pt.x,y:bend.y-pt.y)
                status?("Drag wire bend in X and Y · Delete removes wire")
                needsDisplay = true; return
            }
            selectedWire = nil
            selected = diagram.parts.last(where: { NSRect(x:$0.position.x,y:$0.position.y,width:$0.width,height:$0.height).contains(pt) })?.id
            if let p = diagram.parts.first(where: { $0.id == selected }) { checkpoint(); dragStart = pt; original = p.position; status?(p.label) }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if draggingWire, let i = selectedWire, diagram.wires.indices.contains(i) {
            let pt = convert(event.locationInWindow,from:nil)
            diagram.wires[i].bend = Point(x:max(0,(pt.x+wireDragOffset.x).rounded()),y:max(0,(pt.y+wireDragOffset.y).rounded()))
            needsDisplay = true; return
        }
        guard !wiring, let start = dragStart, let origin = original, let i = diagram.parts.firstIndex(where: { $0.id == selected }) else { return }
        let pt = convert(event.locationInWindow, from: nil)
        diagram.parts[i].position = diagram.placement(of:i,at:Point(x:origin.x+pt.x-start.x,y:origin.y+pt.y-start.y)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil; original = nil; draggingWire = false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pending = nil; selected = nil; selectedWire = nil }
        else if event.keyCode == 51, let i = selectedWire, diagram.wires.indices.contains(i) { checkpoint(); diagram.wires.remove(at:i); selectedWire = nil }
        else if event.keyCode == 51, let id = selected { checkpoint(); diagram.parts.removeAll { $0.id == id }; diagram.wires.removeAll { $0.from.part == id || $0.to.part == id }; selected = nil }
        needsDisplay = true
    }
}
extension NSColor {
    convenience init(hex: String) { let n = UInt64(hex.dropFirst(), radix:16) ?? 0; self.init(red: Double((n>>16)&255)/255, green: Double((n>>8)&255)/255, blue: Double(n&255)/255, alpha: 1) }
}
@MainActor final class App: NSObject, NSApplicationDelegate {
    let canvas = Canvas(frame: NSRect(x:0,y:0,width:1400,height:900))
    var window: NSWindow!
    var projectURL: URL?
    let status = NSTextField(labelWithString: "Drag parts to arrange · Wire mode: click two pins · Wire mode off: drag wires in X/Y · Delete removes selection")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = "Graphical Circuits — Kavrous"; window.center()
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 0; root.alignment = .leading
        let bar = NSStackView(); bar.spacing = 8; bar.edgeInsets = NSEdgeInsets(top:12,left:16,bottom:12,right:16)
        for (title,action) in [("Import KiCad",#selector(importPCB)),("Open",#selector(openProject)),("Save",#selector(save)),("Export SVG",#selector(exportSVG)),("Undo",#selector(undo)),("Redo",#selector(redo))] { bar.addArrangedSubview(NSButton(title:title,target:self,action:action)) }
        root.addArrangedSubview(bar)
        let tools = NSStackView(); tools.spacing = 10; tools.edgeInsets = NSEdgeInsets(top:4,left:16,bottom:12,right:16)
        for name in ["Breadboard","LED","Resistor","Capacitor","Header"] { let b = NSButton(title:"+ \(name)",target:self,action:#selector(addPart(_:))); b.identifier = NSUserInterfaceItemIdentifier(name); tools.addArrangedSubview(b) }
        tools.addArrangedSubview(NSButton(checkboxWithTitle:"Wire mode",target:self,action:#selector(mode(_:))))
        let colors = NSPopUpButton(); colors.addItems(withTitles:["Terracotta","Blue","Green","Black","Yellow"]); colors.target = self; colors.action = #selector(color(_:)); tools.addArrangedSubview(colors)
        tools.addArrangedSubview(NSButton(title:"Edit… ⌘E",target:self,action:#selector(editComponent)))
        root.addArrangedSubview(tools)
        let scroll = NSScrollView(); scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true; scroll.documentView = canvas
        root.addArrangedSubview(scroll); root.addArrangedSubview(status)
        window.contentView = root
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo:root.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:300)])
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        canvas.status = { [weak self] text in self?.status.stringValue = text }
        canvas.diagram.add("Breadboard"); canvas.diagram.add("LED"); canvas.diagram.parts[1].position = canvas.diagram.parts[1].placement(at:Point(x:730,y:180))
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(); appMenu.addItem(withTitle:"Quit Graphical Circuits",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); appItem.submenu = appMenu; menu.addItem(appItem); 
        for (title,items) in [("File",[("Open…",#selector(openProject),"o"),("Save",#selector(save),"s")]),("Edit",[("Undo",#selector(undo),"z"),("Redo",#selector(redo),"y"),("Edit Component…",#selector(editComponent),"e")])] {
            let item = NSMenuItem(); item.title = title
            let submenu = NSMenu(title:title)
            for (name,action,key) in items { let command = NSMenuItem(title:name,action:action,keyEquivalent:key); command.target = self; command.keyEquivalentModifierMask = .command; submenu.addItem(command) }
            item.submenu = submenu; menu.addItem(item)
        }
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    @objc func addPart(_ sender:NSButton) { canvas.checkpoint(); canvas.diagram.add(sender.identifier!.rawValue); canvas.needsDisplay = true }
    @objc func mode(_ sender:NSButton) { canvas.wiring = sender.state == .on; canvas.pending = nil; canvas.needsDisplay = true }
    @objc func color(_ sender:NSPopUpButton) { canvas.wireColor = ["#dc654c","#3c83b5","#3c9475","#303938","#d4ae39"][sender.indexOfSelectedItem] }
    @objc func undo() { canvas.undoEdit() }
    @objc func redo() { canvas.redoEdit() }
    func report(_ error: Error) { NSAlert(error:error).runModal() }
    @objc func importPCB() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension:"kicad_pcb") ?? .data]
        guard p.runModal() == .OK, let url = p.url else { return }
        do { let part = try importBoard(String(contentsOf:url,encoding:.utf8), name:url.deletingPathExtension().lastPathComponent); canvas.checkpoint(); canvas.diagram.parts.append(part); canvas.needsDisplay = true; status.stringValue = "Imported \(part.pins.count) pads · Edge.Cuts outline, silkscreen, drill holes and package geometry" } catch { report(error) }
    }
    @objc func openProject() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        do { let d = try JSONDecoder().decode(Diagram.self,from:Data(contentsOf:url)); canvas.checkpoint(); canvas.diagram = d; projectURL = url; canvas.selectedWire = nil; canvas.pending = nil; canvas.selected = nil; canvas.needsDisplay = true } catch { report(error) }
    }
    func write(_ data:Data, name:String, type:UTType) { let p = NSSavePanel(); p.nameFieldStringValue = name; p.allowedContentTypes = [type]; guard p.runModal() == .OK, let url = p.url else { return }; do { try data.write(to:url,options:.atomic); status.stringValue = "Saved \(url.lastPathComponent)" } catch { report(error) } }
    @objc func save() {
        do {
            let data = try JSONEncoder().encode(canvas.diagram)
            var destination = projectURL
            if destination == nil {
                let panel = NSSavePanel(); panel.nameFieldStringValue = "Circuit.json"; panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK else { return }; destination = panel.url
            }
            guard let url = destination else { return }
            try data.write(to:url,options:.atomic); projectURL = url; status.stringValue = "Saved \(url.lastPathComponent)"
        } catch { report(error) }
    }
    @objc func exportSVG() { write(Data(canvas.diagram.svg().utf8),name:"Circuit.svg",type:.svg) }
    @objc func editComponent() {
        guard let part = canvas.diagram.parts.first(where: { $0.id == canvas.selected }) else {
            status.stringValue = "Select a component with Wire mode off, then press ⌘E to edit it."
            return
        }
        let isValue = ["Resistor","Capacitor"].contains(part.kind)
        let alert = NSAlert()
        alert.messageText = "Edit \(part.kind.lowercased())"
        alert.informativeText = part.kind == "Resistor" ? "Resistance, e.g. 220 Ω or 4.7 kΩ. Bands follow values that fit a four-band code (gold tolerance)." : part.kind == "Capacitor" ? "Capacitance, e.g. 100 nF or 0.1 µF. This is a non-polarized ceramic capacitor." : "Edit the component label\(part.kind == "LED" ? " and lens color." : ".")"
        let field = NSTextField(string:part.label)
        field.placeholderString = isValue ? "Value" : "Label"
        let fields = NSStackView(); fields.orientation = .vertical; fields.alignment = .leading; fields.spacing = 8
        fields.addArrangedSubview(NSTextField(labelWithString:isValue ? "Value" : "Label")); fields.addArrangedSubview(field)
        let colors = NSPopUpButton()
        if part.kind == "LED" {
            fields.addArrangedSubview(NSTextField(labelWithString:"LED color"))
            colors.addItems(withTitles:LEDColor.allCases.map(\.rawValue))
            colors.selectItem(withTitle:(part.ledColor ?? .red).rawValue)
            fields.addArrangedSubview(colors)
        }
        fields.frame = NSRect(x:0,y:0,width:340,height:part.kind == "LED" ? 112 : 54)
        field.widthAnchor.constraint(equalToConstant:340).isActive = true
        alert.accessoryView = fields; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            guard !field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                alert.messageText = "Enter a \(isValue ? "value" : "label")"; continue
            }
            canvas.editSelectedPart(label:field.stringValue,ledColor:part.kind == "LED" ? LEDColor(rawValue:colors.titleOfSelectedItem ?? "Red") : nil)
            status.stringValue = "Updated \(part.kind.lowercased())"
            break
        }
    }
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()

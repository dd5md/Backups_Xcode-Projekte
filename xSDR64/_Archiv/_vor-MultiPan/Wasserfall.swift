import ApiPackage
import MetalKit
import os
import SwiftUI

// MARK: - Empfang (UDP-Empfangs-Queue)

/// Setzt die Wasserfall-Pakete zu ganzen Zeilen zusammen.
/// Paket-Kopf (36 Byte, Big Endian):
///   Frequenz erster Wert u64 | Hz je Wert u64 (beide ×1.048576e6) | Zeilendauer u32 |
///   Werte in diesem Paket u16 | Höhe u16 | Zeilennummer u32 | Auto-Schwarzwert u32 |
///   Werte in der ganzen Zeile u16 | Startindex u16
nonisolated final class WasserfallEmpfang: @unchecked Sendable {
  static let shared = WasserfallEmpfang()

  private struct Sammlung {
    var bins = [UInt16]()
    var zeile: UInt32?
    var gesammelt = 0
  }
  private var sammlungen = [UInt32: Sammlung]()

  var rueckruf: @Sendable (UInt32, [UInt8]) -> Void {
    { [self] id, payload in self.paket(id, payload) }
  }

  func paket(_ id: UInt32, _ p: [UInt8]) {
    guard p.count >= 36 else { return }
    func u16(_ o: Int) -> Int { Int(p[o]) << 8 | Int(p[o + 1]) }
    func u32(_ o: Int) -> UInt32 { UInt32(p[o]) << 24 | UInt32(p[o + 1]) << 16 | UInt32(p[o + 2]) << 8 | UInt32(p[o + 3]) }
    func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) << 32 | UInt64(u32(o + 4)) }
    let ersteHz = Double(u64(0)) / 1.048576e6
    let binHz = Double(u64(8)) / 1.048576e6
    let anzahl = u16(20)
    let zeile = u32(24)
    let autoSchwarz = u32(28)
    let gesamt = u16(32)
    let start = u16(34)
    guard gesamt > 0, start + anzahl <= gesamt, p.count >= 36 + anzahl * 2 else { return }

    var s = sammlungen[id] ?? Sammlung()
    if start == 0 {
      s.zeile = zeile
      s.gesammelt = 0
      if s.bins.count != gesamt { s.bins = [UInt16](repeating: 0, count: gesamt) }
    }
    guard s.zeile == zeile, s.bins.count == gesamt else { sammlungen[id] = s; return }

    for i in 0..<anzahl {
      s.bins[start + i] = UInt16(p[36 + 2 * i]) << 8 | UInt16(p[37 + 2 * i])
    }
    s.gesammelt += anzahl

    if s.gesammelt >= gesamt {
      let fertig = s.bins
      s.zeile = nil
      s.gesammelt = 0
      // Zeilen kommen nur ~12 mal pro Sekunde – keine geht verloren
      DispatchQueue.main.async {
        WasserfallSpeicher.shared.neueZeile(id, fertig, ersteHz: ersteHz, binHz: binHz, autoSchwarz: autoSchwarz)
      }
    }
    sammlungen[id] = s
  }
}

// MARK: - Speicher auf der Grafikkarte

/// Ringpuffer der Wasserfall-Zeilen als Metal-Textur
@MainActor
final class WasserfallSpeicher {
  static let shared = WasserfallSpeicher()

  static let reihen = 2048   // so viele Zeilen werden aufgehoben
  static let breite = 4096   // max. Werte je Zeile

  let device: MTLDevice?
  let zeilen: MTLTexture?
  let zeilenInfo: MTLBuffer?   // je Reihe: (Frequenz erster Wert, Hz je Wert) als Float
  private(set) var oben = 0
  private(set) var werteJeZeile = 0
  private(set) var autoSchwarz: UInt32 = 0

  /// Nur Zeilen dieses Wasserfalls annehmen (der unseres Panadapters)
  var aktiveId: UInt32 = 0

  /// Die Anzeige, die bei neuer Zeile neu zeichnen soll
  weak var ansicht: MTKView?

  private init() {
    device = MTLCreateSystemDefaultDevice()
    let d = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Uint, width: Self.breite, height: Self.reihen, mipmapped: false)
    d.usage = .shaderRead
    zeilen = device?.makeTexture(descriptor: d)
    zeilenInfo = device?.makeBuffer(length: Self.reihen * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared)
    if let zeilenInfo { memset(zeilenInfo.contents(), 0, zeilenInfo.length) }
  }

  func neueZeile(_ id: UInt32, _ bins: [UInt16], ersteHz: Double, binHz: Double, autoSchwarz: UInt32) {
    guard id == aktiveId, let zeilen, let zeilenInfo, !bins.isEmpty else { return }
    let n = min(bins.count, Self.breite)
    oben = (oben + 1) % Self.reihen
    bins.withUnsafeBytes { ptr in
      zeilen.replace(region: MTLRegionMake2D(0, oben, n, 1), mipmapLevel: 0,
                     withBytes: ptr.baseAddress!, bytesPerRow: n * 2)
    }
    zeilenInfo.contents().assumingMemoryBound(to: SIMD2<Float>.self)[oben] = SIMD2(Float(ersteHz), Float(binHz))
    werteJeZeile = n
    self.autoSchwarz = autoSchwarz
    ansicht?.needsDisplay = true
  }

  /// Beim Wechsel des Wasserfalls alte Zeilen verwerfen
  func leeren() {
    if let zeilenInfo { memset(zeilenInfo.contents(), 0, zeilenInfo.length) }
  }
}

// MARK: - Anzeige

/// Werte für den Shader – gleicher Aufbau wie `WasserfallWerte` in Wasserfall.metal
private struct WasserfallWerte {
  var startHz: Float
  var spanHz: Float
  var oben: UInt32
  var reihen: UInt32
  var breite: UInt32
  var bildReihen: UInt32
  var schwarz: Float
  var verstaerkung: Float
}

/// Wasserfall-Anzeige mit Metal. Zeichnet nur, wenn eine neue Zeile kommt oder sich etwas ändert.
struct WasserfallAnsicht: NSViewRepresentable {
  let pan: Panadapter?
  let wasserfall: Waterfall?

  func makeCoordinator() -> Zeichner { Zeichner() }

  func makeNSView(context: Context) -> MTKView {
    let speicher = WasserfallSpeicher.shared
    let view = MTKView(frame: .zero, device: speicher.device)
    view.delegate = context.coordinator
    view.isPaused = true                 // kein Dauer-Zeichnen …
    view.enableSetNeedsDisplay = true    // … nur auf Anforderung (spart Prozessor)
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0.05, alpha: 1)
    context.coordinator.vorbereiten(view)
    speicher.ansicht = view
    return view
  }

  func updateNSView(_ view: MTKView, context: Context) {
    let z = context.coordinator
    let speicher = WasserfallSpeicher.shared
    let neueId = wasserfall?.id ?? 0
    if speicher.aktiveId != neueId {
      speicher.aktiveId = neueId
      speicher.leeren()
    }
    if let pan, pan.bandwidth > 0 {
      z.startHz = Double(pan.center) - Double(pan.bandwidth) / 2
      z.spanHz = Double(pan.bandwidth)
    }
    if let wasserfall {
      z.autoSchwarzAn = wasserfall.autoBlackEnabled
      z.schwarzwert = wasserfall.blackLevel
      z.verstaerkung = wasserfall.colorGain
    }
    view.needsDisplay = true
  }

  final class Zeichner: NSObject, MTKViewDelegate {
    var startHz: Double = 14_000_000
    var spanHz: Double = 200_000
    var autoSchwarzAn = true
    var schwarzwert = 0
    var verstaerkung = 30

    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?

    func vorbereiten(_ view: MTKView) {
      guard let device = view.device, let bib = device.makeDefaultLibrary() else { return }
      queue = device.makeCommandQueue()
      let p = MTLRenderPipelineDescriptor()
      p.vertexFunction = bib.makeFunction(name: "wasserfall_vertex")
      p.fragmentFunction = bib.makeFunction(name: "wasserfall_fragment")
      p.colorAttachments[0].pixelFormat = view.colorPixelFormat
      pipeline = try? device.makeRenderPipelineState(descriptor: p)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
      view.needsDisplay = true
    }

    func draw(in view: MTKView) {
      MainActor.assumeIsolated { zeichne(view) }
    }

    @MainActor private func zeichne(_ view: MTKView) {
      let speicher = WasserfallSpeicher.shared
      guard let queue, let pipeline, let zeilen = speicher.zeilen, let info = speicher.zeilenInfo,
            let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
            let befehle = queue.makeCommandBuffer(),
            let enc = befehle.makeRenderCommandEncoder(descriptor: pass) else { return }

      let schwarz: Float = autoSchwarzAn
        ? Float(speicher.autoSchwarz)
        : Float(schwarzwert) / 100 * Float(UInt16.max)
      var w = WasserfallWerte(
        startHz: Float(startHz), spanHz: Float(spanHz),
        oben: UInt32(speicher.oben), reihen: UInt32(WasserfallSpeicher.reihen),
        breite: UInt32(max(1, speicher.werteJeZeile)),
        bildReihen: UInt32(max(1, view.bounds.height)),
        schwarz: schwarz, verstaerkung: Float(verstaerkung))

      enc.setRenderPipelineState(pipeline)
      enc.setFragmentTexture(zeilen, index: 0)
      enc.setFragmentBuffer(info, offset: 0, index: 0)
      enc.setFragmentBytes(&w, length: MemoryLayout<WasserfallWerte>.stride, index: 1)
      enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      enc.endEncoding()
      befehle.present(drawable)
      befehle.commit()
    }
  }
}

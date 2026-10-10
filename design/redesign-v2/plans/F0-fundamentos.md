# Rediseño v2 · F0 Fundamentos — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** añadir los tokens v2 (color, tipografía, espaciado, radios, densidad, grafo y lanes) junto al sistema v1, sin cambiar nada visible salvo la desaparición de la densidad `comfy`.

**Arquitectura:**
- **Tipos nuevos** en `gitForge/DesignSystem/Theme/V2/`.
- **Cálculo de color** puro sobre hex `UInt32` (`ColorMath`). Todo lo que pueda usar el renderer del grafo es `nonisolated`.
- **`AppTheme` expone `colors: GFColors`** junto a `palette: ThemePalette`. Las pantallas no se tocan: las fases F1-F8 migran cada una a los tokens v2, y F9 borra los v1.

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, así que los tipos que deban poder usarse fuera del main actor llevan `nonisolated` explícito. Tests con Swift Testing.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md), §3, §4 y §7 (F0).

## Restricciones globales

- Los valores de color, tipografía, espaciado, radios y tamaños se copian **exactos** de la spec §4. No se inventa ningún valor.
- Ningún tipo v2 llama a `Color(hex:)` desde contexto `nonisolated` (`Color(hex:)` es `@MainActor` por la isolation por defecto). En contexto `nonisolated` se usa `Color(.sRGB, red:green:blue:opacity:)`.
- No se modifica ninguna vista de `Features/` ni de `DesignSystem/Components/`. La única excepción es `AppearanceSection`, que hereda sola la desaparición de `comfy` a través de `Density.allCases`, sin editarla.
- Los valores v1 (`Density.rowHeight`, `Density.monoFontSize`, `ThemePalette`, `FontSize`, `DesignTokens.*`) **no cambian**.
- La build termina con 0 warnings y los commits siguen el formato `type: description`, sin `Co-Authored-By`.
- No se hace push sin aprobación explícita de Alvaro.

## Riesgos a revisar

1. **Un acento guardado que no es uno de los 4 swatches** (por ejemplo `#FF0000`, o un gris sin tono) → `AccentSwatch.nearest` devuelve un swatch válido sin fallar. Test en la Tarea 2.
2. **Densidad guardada como `comfy`, vacía o con un valor desconocido** → se lee `.regular`. Test en la Tarea 6.
3. **`branchId` negativo o extremo** (`Int.min`, `Int.max`) → lane válido sin overflow ni crash. Test en la Tarea 7.
4. **La rama HEAD es `main`** → gana el acento, no lane0. Test en la Tarea 7.
5. **Alto contraste con un swatch que no es violeta** → el `fg` derivado llega a 7:1 y el bucle de `raise` termina aunque el objetivo sea imposible. Tests en las Tareas 1 y 2.

## Mapa de ficheros

| Fichero | Responsabilidad |
|---|---|
| Crear `gitForge/DesignSystem/Theme/V2/ColorMath.swift` | Luminancia, contraste, tono, mezcla y ajuste de contraste sobre hex. `nonisolated`. |
| Crear `gitForge/DesignSystem/Theme/V2/ThemeVariant.swift` | Las 4 variantes de tema y su `bg.content`. `nonisolated`. |
| Crear `gitForge/DesignSystem/Theme/V2/AccentSwatch.swift` | Los 4 acentos, sus valores derivados y `nearest`. `nonisolated`. |
| Crear `gitForge/DesignSystem/Theme/V2/GFColors.swift` | Tokens de color v2 (spec §4.1). |
| Modificar `gitForge/DesignSystem/Theme/AppTheme.swift` | `colors`, `accentSwatch`, refresco conjunto y lectura de la densidad con `Density.resolve`. |
| Crear `gitForge/DesignSystem/Theme/V2/TypeRole.swift` | 8 roles tipográficos, `AppFont.font(_:)` y `.textRole(_:)`. |
| Crear `gitForge/DesignSystem/Theme/V2/Spacing.swift` | `Spacing` y `Radius` v2. |
| Crear `gitForge/DesignSystem/Theme/V2/GraphMetrics.swift` | Métricas del grafo por densidad. `nonisolated`. |
| Crear `gitForge/DesignSystem/Theme/V2/DensityMetrics.swift` | Alturas y anchos por densidad. `nonisolated`. |
| Modificar `gitForge/DesignSystem/Theme/Density.swift` | Quitar `comfy`, añadir `resolve` y `metrics`. |
| Crear `gitForge/DesignSystem/Theme/V2/LaneColors.swift` | Asignación y color de lanes v2. `nonisolated`. |
| Tests en `gitForgeTests/DesignSystem/Theme/V2/` | Un fichero por tipo. |

El proyecto usa carpetas sincronizadas (`objectVersion = 77`), así que los ficheros nuevos entran en el target sin tocar el `.pbxproj`.

**Ejecutar una suite:**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

---

### Tarea 1: `ColorMath` y rama de trabajo

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/ColorMath.swift`
- Test: `gitForgeTests/DesignSystem/Theme/V2/ColorMathTests.swift`

**Interfaces:**
- Produce:
  - `ColorMath.components(_: UInt32) -> (r: Double, g: Double, b: Double)`
  - `ColorMath.hex(r:g:b:) -> UInt32`
  - `luminance(_:) -> Double`
  - `contrast(_:_:) -> Double`
  - `hue(_:) -> Double`
  - `hueDistance(_:_:) -> Double`
  - `mix(_:toward:fraction:) -> UInt32`
  - `raise(_:toContrast:on:toward:) -> UInt32`

- [ ] **Paso 1: Crear la rama**

```bash
git checkout main && git pull --ff-only && git checkout -b feat/redesign-f0-foundations
```

- [ ] **Paso 2: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("ColorMath")
struct ColorMathTests {

    @Test("Black on white is the WCAG maximum, a colour on itself the minimum")
    func contrastBounds() {
        #expect(abs(ColorMath.contrast(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(ColorMath.contrast(0x7C5CFF, 0x7C5CFF) - 1) < 0.0001)
    }

    @Test("Hue follows the HSV wheel; greys report 0")
    func hue() {
        #expect(ColorMath.hue(0xFF0000) == 0)
        #expect(abs(ColorMath.hue(0x00FF00) - 120) < 0.001)
        #expect(abs(ColorMath.hue(0x0000FF) - 240) < 0.001)
        #expect(abs(ColorMath.hue(0xFF0080) - 330) < 0.5)
        #expect(ColorMath.hue(0x808080) == 0)
    }

    @Test("Hue distance takes the short way round the wheel")
    func hueDistance() {
        #expect(abs(ColorMath.hueDistance(0xFF0000, 0xFF00FF) - 60) < 0.001)
        #expect(abs(ColorMath.hueDistance(0xFF0080, 0xFF8000) - 60) < 0.5)
    }

    @Test("Mixing halfway from black to white gives mid grey; the ends are the inputs")
    func mix() {
        #expect(ColorMath.mix(0x000000, toward: 0xFFFFFF, fraction: 0.5) == 0x808080)
        #expect(ColorMath.mix(0x123456, toward: 0xFFFFFF, fraction: 0) == 0x123456)
        #expect(ColorMath.mix(0x123456, toward: 0xFFFFFF, fraction: 1) == 0xFFFFFF)
    }

    @Test("Raise stops at the first step that reaches the ratio")
    func raiseReachesRatio() {
        let raised = ColorMath.raise(0x555555, toContrast: 7, on: 0x000000, toward: 0xFFFFFF)
        #expect(ColorMath.contrast(raised, 0x000000) >= 7)
        #expect(raised != 0xFFFFFF)
    }

    @Test("Raise terminates on an impossible ratio and returns the target")
    func raiseImpossible() {
        #expect(ColorMath.raise(0x555555, toContrast: 30, on: 0x000000, toward: 0xFFFFFF) == 0xFFFFFF)
    }

    @Test("Hex round-trips through components")
    func roundTrip() {
        let c = ColorMath.components(0x7C5CFF)
        #expect(ColorMath.hex(r: c.r, g: c.g, b: c.b) == 0x7C5CFF)
    }
}
```

- [ ] **Paso 3: Ejecutar y comprobar que falla**

Ejecutar la suite `ColorMathTests`. Resultado esperado: error de compilación, `cannot find 'ColorMath' in scope`.

- [ ] **Paso 4: Implementar**

```swift
import Foundation

/// Pure sRGB maths on `0xRRGGBB` values. `nonisolated` so the commit graph
/// renderer, which runs off the main actor, can use it.
nonisolated enum ColorMath {
    static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func hex(r: Double, g: Double, b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG 2 relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let c = components(hex)
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG 2 contrast ratio, `1...21`.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// HSV hue in degrees, `0..<360`. Greys report 0.
    static func hue(_ hex: UInt32) -> Double {
        let c = components(hex)
        let maxV = max(c.r, c.g, c.b), minV = min(c.r, c.g, c.b)
        let delta = maxV - minV
        guard delta > 0 else { return 0 }
        let sector: Double
        if maxV == c.r {
            sector = (c.g - c.b) / delta
        } else if maxV == c.g {
            sector = (c.b - c.r) / delta + 2
        } else {
            sector = (c.r - c.g) / delta + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Shortest distance between two hues on the colour wheel, `0...180`.
    static func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
        let d = abs(hue(a) - hue(b))
        return min(d, 360 - d)
    }

    /// Straight sRGB blend: `fraction` 0 returns `hex`, 1 returns `target`.
    static func mix(_ hex: UInt32, toward target: UInt32, fraction: Double) -> UInt32 {
        let a = components(hex), b = components(target)
        return Self.hex(
            r: a.r + (b.r - a.r) * fraction,
            g: a.g + (b.g - a.g) * fraction,
            b: a.b + (b.b - a.b) * fraction
        )
    }

    /// Steps `hex` toward `target` in 5 % increments until it reaches `ratio`
    /// against `background`. Returns `target` when no step gets there.
    static func raise(_ hex: UInt32, toContrast ratio: Double, on background: UInt32, toward target: UInt32) -> UInt32 {
        for step in 0...20 {
            let candidate = mix(hex, toward: target, fraction: Double(step) * 0.05)
            if contrast(candidate, background) >= ratio { return candidate }
        }
        return target
    }
}
```

- [ ] **Paso 5: Ejecutar y comprobar que pasa**

Ejecutar la suite `ColorMathTests`. Resultado esperado: 7 tests en verde.

- [ ] **Paso 6: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/ColorMath.swift gitForgeTests/DesignSystem/Theme/V2/ColorMathTests.swift
git commit -m "feat: add ColorMath for v2 design tokens"
```

---

### Tarea 2: `ThemeVariant` y `AccentSwatch`

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/ThemeVariant.swift`
- Crear: `gitForge/DesignSystem/Theme/V2/AccentSwatch.swift`
- Test: `gitForgeTests/DesignSystem/Theme/V2/AccentSwatchTests.swift`

**Interfaces:**
- Consume: `ColorMath.raise`, `ColorMath.hueDistance` y `ColorMath.contrast` (Tarea 1).
- Produce:
  - `ThemeVariant` (`.dark`, `.light`, `.highContrastDark`, `.highContrastLight`), con `init(isDark:highContrast:)`, `isDark`, `isHighContrast` y `contentBackground: UInt32`.
  - `AccentSwatch` (`.violet`, `.green`, `.coral`, `.blue`), con `swatch`, `fill`, `onFill`, `foreground(for: ThemeVariant) -> UInt32` y `static nearest(toHex:) -> AccentSwatch`.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccentSwatch")
struct AccentSwatchTests {

    @Test("Variant resolves from the effective scheme and Increase Contrast")
    func variant() {
        #expect(ThemeVariant(isDark: true, highContrast: false) == .dark)
        #expect(ThemeVariant(isDark: false, highContrast: false) == .light)
        #expect(ThemeVariant(isDark: true, highContrast: true) == .highContrastDark)
        #expect(ThemeVariant(isDark: false, highContrast: true) == .highContrastLight)
    }

    @Test("Swatch values match the design sheet")
    func values() {
        #expect(AccentSwatch.violet.fill == 0x7350FA)
        #expect(AccentSwatch.violet.onFill == 0xFFFFFF)
        #expect(AccentSwatch.green.onFill == 0x101014)
        #expect(AccentSwatch.coral.foreground(for: .dark) == 0xFF907F)
        #expect(AccentSwatch.blue.foreground(for: .light) == 0x1F66CC)
        #expect(AccentSwatch.violet.foreground(for: .highContrastDark) == 0xBBAAFF)
        #expect(AccentSwatch.violet.foreground(for: .highContrastLight) == 0x4321D9)
    }

    @Test("Text on the accent fill meets AA for every swatch", arguments: AccentSwatch.allCases)
    func onFillContrast(swatch: AccentSwatch) {
        #expect(ColorMath.contrast(swatch.onFill, swatch.fill) >= 4.5)
    }

    @Test("High-contrast foregrounds reach 7:1 on bg.content", arguments: AccentSwatch.allCases)
    func highContrastForeground(swatch: AccentSwatch) {
        for variant in [ThemeVariant.highContrastDark, .highContrastLight] {
            #expect(ColorMath.contrast(swatch.foreground(for: variant), variant.contentBackground) >= 7, "\(swatch) \(variant)")
        }
    }

    @Test("A stored swatch maps to itself")
    func exactMatch() {
        for swatch in AccentSwatch.allCases {
            #expect(AccentSwatch.nearest(toHex: swatch.swatch) == swatch)
        }
    }

    @Test("Any other colour maps to the swatch with the closest hue, greys included")
    func nearest() {
        #expect(AccentSwatch.nearest(toHex: 0x0000FF) == .violet)
        #expect(AccentSwatch.nearest(toHex: 0x2080FF) == .blue)
        #expect(AccentSwatch.nearest(toHex: 0x00C080) == .green)
        #expect(AccentSwatch.nearest(toHex: 0xFF0000) == .coral)
        #expect(AccentSwatch.allCases.contains(AccentSwatch.nearest(toHex: 0x808080)))
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `AccentSwatchTests`. Resultado esperado: error de compilación, `cannot find 'ThemeVariant' in scope`.

- [ ] **Paso 3: Implementar `ThemeVariant.swift`**

```swift
import Foundation

/// The four colour variants of the v2 palette (redesign spec §4.1).
nonisolated enum ThemeVariant: CaseIterable, Sendable {
    case dark
    case light
    case highContrastDark
    case highContrastLight

    init(isDark: Bool, highContrast: Bool) {
        switch (isDark, highContrast) {
        case (true, false): self = .dark
        case (false, false): self = .light
        case (true, true): self = .highContrastDark
        case (false, true): self = .highContrastLight
        }
    }

    var isDark: Bool { self == .dark || self == .highContrastDark }
    var isHighContrast: Bool { self == .highContrastDark || self == .highContrastLight }

    /// `bg.content`, the surface most text sits on. Contrast targets are
    /// measured against it.
    var contentBackground: UInt32 {
        switch self {
        case .dark: 0x18181C
        case .light: 0xFFFFFF
        case .highContrastDark: 0x0A0A0C
        case .highContrastLight: 0xFFFFFF
        }
    }
}
```

- [ ] **Paso 4: Implementar `AccentSwatch.swift`**

```swift
import Foundation

/// The user-selectable accents and the values derived from each one
/// (redesign spec §4.1.1).
nonisolated enum AccentSwatch: CaseIterable, Sendable {
    case violet
    case green
    case coral
    case blue

    /// The colour shown in pickers and persisted under `appTheme.accent`.
    var swatch: UInt32 {
        switch self {
        case .violet: 0x7C5CFF
        case .green: 0x56B497
        case .coral: 0xFF7E6B
        case .blue: 0x5DA4FF
        }
    }

    /// Fill under text and buttons. Violet is deepened so white text on it
    /// reaches 4.9:1.
    var fill: UInt32 { self == .violet ? 0x7350FA : swatch }

    /// Text and glyphs drawn on `fill`.
    var onFill: UInt32 { self == .violet ? 0xFFFFFF : 0x101014 }

    /// Accent used for text, icons and the HEAD lane.
    func foreground(for variant: ThemeVariant) -> UInt32 {
        switch variant {
        case .dark:
            switch self {
            case .violet: 0xA08CFF
            case .green: 0x5FCDA9
            case .coral: 0xFF907F
            case .blue: 0x79B6FF
            }
        case .light:
            switch self {
            case .violet: 0x5B3DF5
            case .green: 0x1F7F5F
            case .coral: 0xC0452F
            case .blue: 0x1F66CC
            }
        case .highContrastDark:
            self == .violet
                ? 0xBBAAFF
                : ColorMath.raise(foreground(for: .dark), toContrast: 7, on: variant.contentBackground, toward: 0xFFFFFF)
        case .highContrastLight:
            self == .violet
                ? 0x4321D9
                : ColorMath.raise(foreground(for: .light), toContrast: 7, on: variant.contentBackground, toward: 0x000000)
        }
    }

    /// The swatch a stored accent maps to: itself when it is one, otherwise
    /// the closest hue. Older builds could persist any colour.
    static func nearest(toHex hex: UInt32) -> AccentSwatch {
        if let exact = allCases.first(where: { $0.swatch == hex }) { return exact }
        return allCases.min {
            ColorMath.hueDistance($0.swatch, hex) < ColorMath.hueDistance($1.swatch, hex)
        } ?? .violet
    }
}
```

- [ ] **Paso 5: Ejecutar y comprobar que pasa**

Ejecutar la suite `AccentSwatchTests`. Resultado esperado: todos en verde (los tests con argumentos cuentan uno por swatch).

- [ ] **Paso 6: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/ThemeVariant.swift gitForge/DesignSystem/Theme/V2/AccentSwatch.swift gitForgeTests/DesignSystem/Theme/V2/AccentSwatchTests.swift
git commit -m "feat: add v2 theme variants and accent swatches"
```

---

### Tarea 3: `GFColors` y `AppTheme.colors`

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/GFColors.swift`
- Modificar: `gitForge/DesignSystem/Theme/AppTheme.swift` (propiedades junto a `palette`, en la línea 43; `refreshPalette()` en las líneas 66-68)
- Test: `gitForgeTests/DesignSystem/Theme/V2/GFColorsTests.swift`

**Interfaces:**
- Consume: `ThemeVariant`, `AccentSwatch` (Tarea 2) y `ColorMath` (Tarea 1).
- Produce:
  - `GFColors.make(_ variant: ThemeVariant, accent: AccentSwatch) -> GFColors`, con los campos `bgWindow`, `bgContent`, `bgElevated`, `bgCode`, `glassTint`, `fillControl`, `fillHover`, `separator`, `strokeControl`, `textPrimary`, `textSecondary`, `textTertiary`, `textQuaternary`, `accent`, `accentSoft`, `accentFill`, `accentOnFill`, `add`, `addSoft`, `del`, `delSoft`, `mod`, `modSoft`, `warn`, `warnSoft`, `ok`, `okSoft`, `info`, `infoSoft`, `shadow` y `opaqueGlass: Bool`.
  - `AppTheme.colors: GFColors` y `AppTheme.accentSwatch: AccentSwatch`.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// WCAG guard for the v2 palette (redesign spec §8). Every text token must
/// reach AA (4.5:1) on bg.content and bg.elevated in all four variants.
@Suite("GFColors")
@MainActor
struct GFColorsTests {

    private static func hex(_ color: Color) -> UInt32 {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return ColorMath.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    private static func textTokens(_ colors: GFColors) -> [(String, Color)] {
        [
            ("textPrimary", colors.textPrimary), ("textSecondary", colors.textSecondary),
            ("textTertiary", colors.textTertiary), ("textQuaternary", colors.textQuaternary),
            ("accent", colors.accent), ("add", colors.add), ("del", colors.del), ("mod", colors.mod),
            ("warn", colors.warn), ("ok", colors.ok), ("info", colors.info),
        ]
    }

    @Test("Every text token meets AA on bg.content and bg.elevated", arguments: ThemeVariant.allCases)
    func textContrast(variant: ThemeVariant) {
        for swatch in AccentSwatch.allCases {
            let colors = GFColors.make(variant, accent: swatch)
            let backgrounds = [Self.hex(colors.bgContent), Self.hex(colors.bgElevated)]
            for (name, token) in Self.textTokens(colors) {
                let worst = backgrounds.map { ColorMath.contrast(Self.hex(token), $0) }.min()!
                #expect(worst >= 4.5, "\(variant) \(swatch) \(name): \(worst)")
            }
        }
    }

    @Test("Values match the design sheet")
    func sheetValues() {
        let dark = GFColors.make(.dark, accent: .violet)
        #expect(Self.hex(dark.bgWindow) == 0x141418)
        #expect(Self.hex(dark.textQuaternary) == 0x888893)
        #expect(Self.hex(dark.accent) == 0xA08CFF)
        #expect(Self.hex(dark.accentFill) == 0x7350FA)
        let light = GFColors.make(.light, accent: .blue)
        #expect(Self.hex(light.bgElevated) == 0xF6F6F9)
        #expect(Self.hex(light.warn) == 0xA35A00)
        #expect(Self.hex(light.accent) == 0x1F66CC)
        #expect(Self.hex(light.accentOnFill) == 0x101014)
    }

    @Test("Glass turns opaque only with Increase Contrast")
    func opaqueGlass() {
        #expect(!GFColors.make(.dark, accent: .violet).opaqueGlass)
        #expect(!GFColors.make(.light, accent: .violet).opaqueGlass)
        #expect(GFColors.make(.highContrastDark, accent: .violet).opaqueGlass)
        #expect(GFColors.make(.highContrastLight, accent: .violet).opaqueGlass)
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `GFColorsTests`. Resultado esperado: error de compilación, `cannot find 'GFColors' in scope`.

- [ ] **Paso 3: Implementar `GFColors.swift`**

```swift
import SwiftUI

/// v2 colour tokens (redesign spec §4.1), read through `theme.colors`.
/// Coexists with the v1 `ThemePalette` until phase F9 removes it.
struct GFColors: Equatable, Sendable {
    var bgWindow: Color
    var bgContent: Color
    var bgElevated: Color
    var bgCode: Color
    var glassTint: Color
    var fillControl: Color
    var fillHover: Color
    var separator: Color
    var strokeControl: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var textQuaternary: Color
    var accent: Color
    var accentSoft: Color
    var accentFill: Color
    var accentOnFill: Color
    var add: Color
    var addSoft: Color
    var del: Color
    var delSoft: Color
    var mod: Color
    var modSoft: Color
    var warn: Color
    var warnSoft: Color
    var ok: Color
    var okSoft: Color
    var info: Color
    var infoSoft: Color
    var shadow: Color
    /// Glass surfaces render opaque (Increase Contrast). Reduce Transparency
    /// is honoured by the glass components themselves.
    var opaqueGlass: Bool

    static func make(_ variant: ThemeVariant, accent: AccentSwatch) -> GFColors {
        func pick<T>(_ dark: T, _ light: T, _ hcDark: T, _ hcLight: T) -> T {
            switch variant {
            case .dark: dark
            case .light: light
            case .highContrastDark: hcDark
            case .highContrastLight: hcLight
            }
        }
        func solid(_ dark: UInt32, _ light: UInt32, _ hcDark: UInt32, _ hcLight: UInt32) -> Color {
            Color(hex: pick(dark, light, hcDark, hcLight))
        }
        func white(_ alpha: Double) -> Color { Color(hex: 0xFFFFFF, alpha: alpha) }
        func black(_ alpha: Double) -> Color { Color(hex: 0x000000, alpha: alpha) }
        let accentForeground = accent.foreground(for: variant)

        return GFColors(
            bgWindow: solid(0x141418, 0xE8E8ED, 0x000000, 0xFFFFFF),
            bgContent: solid(0x18181C, 0xFFFFFF, 0x0A0A0C, 0xFFFFFF),
            bgElevated: solid(0x1C1C21, 0xF6F6F9, 0x121216, 0xF2F2F5),
            bgCode: solid(0x17171B, 0xFBFBFD, 0x000000, 0xFFFFFF),
            glassTint: pick(Color(hex: 0x282830, alpha: 0.62), Color(hex: 0xF8F8FB, alpha: 0.72), Color(hex: 0x16161A), Color(hex: 0xF2F2F5)),
            fillControl: pick(white(0.07), black(0.05), white(0.14), black(0.08)),
            fillHover: pick(white(0.055), black(0.04), white(0.12), black(0.08)),
            separator: pick(white(0.07), black(0.08), white(0.32), black(0.38)),
            strokeControl: pick(white(0.10), black(0.10), white(0.55), black(0.60)),
            textPrimary: solid(0xECECF1, 0x1B1B22, 0xFFFFFF, 0x000000),
            textSecondary: solid(0xB9B9C4, 0x3F3F4A, 0xE2E2EA, 0x1E1E26),
            textTertiary: solid(0xA3A3AE, 0x5A5A66, 0xCACAD4, 0x33333D),
            textQuaternary: solid(0x888893, 0x63636E, 0xB4B4C0, 0x44444F),
            accent: Color(hex: accentForeground),
            accentSoft: pick(
                Color(hex: accent.swatch, alpha: 0.24), Color(hex: accent.swatch, alpha: 0.14),
                Color(hex: accent.swatch, alpha: 0.40), Color(hex: accentForeground, alpha: 0.22)
            ),
            accentFill: Color(hex: accent.fill),
            accentOnFill: Color(hex: accent.onFill),
            add: solid(0x6FD8A4, 0x167650, 0x8CF0BE, 0x0B6B42),
            addSoft: pick(Color(hex: 0x46C88C, alpha: 0.14), Color(hex: 0x28AA6E, alpha: 0.12), Color(hex: 0x46C88C, alpha: 0.30), Color(hex: 0x0B6B42, alpha: 0.18)),
            del: solid(0xFF8A8A, 0xC8373D, 0xFFA8A8, 0xA3141B),
            delSoft: pick(Color(hex: 0xFF5F5F, alpha: 0.14), Color(hex: 0xDC3C46, alpha: 0.10), Color(hex: 0xFF5F5F, alpha: 0.30), Color(hex: 0xA3141B, alpha: 0.16)),
            mod: solid(0xF0C066, 0x9A6200, 0xFFD27A, 0x6E4500),
            modSoft: pick(Color(hex: 0xE8B04B, alpha: 0.18), Color(hex: 0xDC9614, alpha: 0.14), Color(hex: 0xE8B04B, alpha: 0.32), Color(hex: 0x6E4500, alpha: 0.16)),
            warn: solid(0xFFB547, 0xA35A00, 0xFFC56B, 0x7A4100),
            warnSoft: pick(Color(hex: 0xFFB547, alpha: 0.16), Color(hex: 0xF09614, alpha: 0.14), Color(hex: 0xFFB547, alpha: 0.32), Color(hex: 0x7A4100, alpha: 0.16)),
            ok: solid(0x5FCDA9, 0x157A5F, 0x7FE6C4, 0x0A5E47),
            okSoft: pick(Color(hex: 0x5FCDA9, alpha: 0.16), Color(hex: 0x1EA078, alpha: 0.12), Color(hex: 0x5FCDA9, alpha: 0.30), Color(hex: 0x0A5E47, alpha: 0.16)),
            info: solid(0x79B6FF, 0x1F64C8, 0x9CCBFF, 0x0A4FA8),
            infoSoft: pick(Color(hex: 0x5DA4FF, alpha: 0.16), Color(hex: 0x286EDC, alpha: 0.12), Color(hex: 0x5DA4FF, alpha: 0.30), Color(hex: 0x0A4FA8, alpha: 0.16)),
            shadow: variant.isDark ? black(0.45) : Color(hex: 0x141428, alpha: 0.14),
            opaqueGlass: variant.isHighContrast
        )
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `GFColorsTests`. Resultado esperado: todos en verde. Si `textContrast` falla con el `accent` de algún swatch en `.light` (verde 4.57 y coral 4.71 están justos sobre blanco), **no se cambian valores**: parar e informar a Alvaro con el ratio exacto.

- [ ] **Paso 5: Conectar `AppTheme`**

En `AppTheme.swift`, debajo de `private(set) var palette: ThemePalette = .dark`:

```swift
    /// v2 colour tokens (redesign spec §4.1). Replaces `palette` once every
    /// screen has migrated (phase F9).
    private(set) var colors: GFColors = .make(.dark, accent: .violet)

    /// The v2 swatch the stored accent maps to.
    var accentSwatch: AccentSwatch {
        let hex = UInt32(accent.hexString.dropFirst(), radix: 16) ?? AccentSwatch.violet.swatch
        return AccentSwatch.nearest(toHex: hex)
    }
```

Sustituir `refreshPalette()` por:

```swift
    private func refreshPalette() {
        palette = ThemePalette.palette(for: effectiveMode, accent: accent, highContrast: increasedContrast)
        colors = .make(ThemeVariant(isDark: effectiveMode == .dark, highContrast: increasedContrast), accent: accentSwatch)
    }
```

- [ ] **Paso 6: Compilar**

```bash
xcodebuild build -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD" | tail -10
```

Resultado esperado: `BUILD SUCCEEDED`, sin líneas `warning:`.

- [ ] **Paso 7: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/GFColors.swift gitForge/DesignSystem/Theme/AppTheme.swift gitForgeTests/DesignSystem/Theme/V2/GFColorsTests.swift
git commit -m "feat: add v2 colour tokens and expose them on AppTheme"
```

---

### Tarea 4: `TypeRole`, `AppFont.font` y `.textRole`

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/TypeRole.swift`
- Test: `gitForgeTests/DesignSystem/Theme/V2/TypeRoleTests.swift`

**Interfaces:**
- Consume: `AppFont.mono(_:weight:family:)`, `MonoFontFamily` (`Typography.swift`) y `\.appTheme` (`EnvironmentValues+Theme.swift`).
- Produce:
  - `TypeRole` (`.largeTitle`, `.title`, `.headline`, `.body`, `.callout`, `.caption`, `.mono`, `.monoSmall`), con `size`, `lineHeight`, `weight: Font.Weight`, `tracking` e `isMono`.
  - `AppFont.font(_ role: TypeRole, weight: Font.Weight? = nil, monoFamily: MonoFontFamily = .systemMono) -> Font`.
  - `View.textRole(_ role: TypeRole, weight: Font.Weight? = nil) -> some View`.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("TypeRole")
struct TypeRoleTests {

    @Test("Sizes and line heights match the design sheet")
    func values() {
        let expected: [(TypeRole, CGFloat, CGFloat)] = [
            (.largeTitle, 28, 34), (.title, 20, 26), (.headline, 15, 20), (.body, 13, 18),
            (.callout, 12, 16), (.caption, 11, 14), (.mono, 12, 19), (.monoSmall, 11, 14),
        ]
        for (role, size, lineHeight) in expected {
            #expect(role.size == size, "\(role)")
            #expect(role.lineHeight == lineHeight, "\(role)")
        }
    }

    @Test("Sans roles grow strictly from caption to largeTitle")
    func sansScale() {
        let sizes = [TypeRole.caption, .callout, .body, .headline, .title, .largeTitle].map(\.size)
        #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("No role uses a half point and every line height clears its size")
    func wholePoints() {
        for role in TypeRole.allCases {
            #expect(role.size.rounded() == role.size, "\(role)")
            #expect(role.lineHeight > role.size, "\(role)")
        }
    }

    @Test("Only the two code roles are monospaced")
    func mono() {
        #expect(TypeRole.allCases.filter(\.isMono) == [.mono, .monoSmall])
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `TypeRoleTests`. Resultado esperado: error de compilación, `cannot find 'TypeRole' in scope`.

- [ ] **Paso 3: Implementar**

```swift
import SwiftUI

/// v2 semantic type roles (redesign spec §4.2). SF Pro for text, the user's
/// code font for the two mono roles. Replaces `FontSize` in phase F9.
nonisolated enum TypeRole: CaseIterable, Sendable {
    case largeTitle
    case title
    case headline
    case body
    case callout
    case caption
    case mono
    case monoSmall

    var size: CGFloat {
        switch self {
        case .largeTitle: 28
        case .title: 20
        case .headline: 15
        case .body: 13
        case .callout: 12
        case .caption: 11
        case .mono: 12
        case .monoSmall: 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 26
        case .headline: 20
        case .body: 18
        case .callout: 16
        case .caption: 14
        case .mono: 19
        case .monoSmall: 14
        }
    }

    /// Default weight. Buttons use `callout` Semibold and column headers
    /// `caption` Semibold by passing `weight:` explicitly.
    var weight: Font.Weight {
        switch self {
        case .largeTitle: .bold
        case .title, .headline: .semibold
        case .caption: .medium
        case .body, .callout, .mono, .monoSmall: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .largeTitle: -0.6
        case .title: -0.3
        case .headline: -0.15
        case .body, .callout, .caption, .mono, .monoSmall: 0
        }
    }

    var isMono: Bool { self == .mono || self == .monoSmall }
}

extension AppFont {
    /// Font for a v2 type role.
    static func font(_ role: TypeRole, weight: Font.Weight? = nil, monoFamily: MonoFontFamily = .systemMono) -> Font {
        let resolvedWeight = weight ?? role.weight
        if role.isMono {
            return mono(role.size, weight: resolvedWeight, family: monoFamily)
        }
        return .system(size: role.size, weight: resolvedWeight)
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: TypeRole
    let weight: Font.Weight?

    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(AppFont.font(role, weight: weight, monoFamily: theme.monoFont))
            .tracking(role.tracking)
            .lineSpacing(role.lineHeight - role.size)
    }
}

extension View {
    /// Applies a v2 type role: font, tracking and line height.
    func textRole(_ role: TypeRole, weight: Font.Weight? = nil) -> some View {
        modifier(TextRoleModifier(role: role, weight: weight))
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `TypeRoleTests`. Resultado esperado: 4 tests en verde.

- [ ] **Paso 5: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/TypeRole.swift gitForgeTests/DesignSystem/Theme/V2/TypeRoleTests.swift
git commit -m "feat: add v2 type roles and textRole modifier"
```

---

### Tarea 5: `Spacing` y `Radius` v2

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/Spacing.swift`
- Test: `gitForgeTests/DesignSystem/Theme/V2/SpacingTests.swift`

**Interfaces:**
- Produce:
  - `Spacing.s2 … s48` (CGFloat).
  - `Radius.badge`, `.chip`, `.controlSmall`, `.row`, `.control`, `.card`, `.popover` y `.panel`.
  - Al ser de nivel superior, no chocan con `DesignTokens.Spacing` ni con `DesignTokens.Radius`, que siempre se escriben cualificados.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Spacing and Radius v2")
struct SpacingTests {

    @Test("Spacing scale matches the sheet, grows strictly and stays on even points")
    func spacing() {
        let scale = [Spacing.s2, Spacing.s4, Spacing.s6, Spacing.s8, Spacing.s12,
                     Spacing.s16, Spacing.s20, Spacing.s24, Spacing.s32, Spacing.s48]
        #expect(scale == [2, 4, 6, 8, 12, 16, 20, 24, 32, 48])
        #expect(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 })
    }

    @Test("Radii match the sheet and grow strictly")
    func radius() {
        let scale = [Radius.badge, Radius.chip, Radius.controlSmall, Radius.row,
                     Radius.control, Radius.card, Radius.popover, Radius.panel]
        #expect(scale == [4, 5, 6, 7, 8, 12, 14, 18])
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `SpacingTests`. Resultado esperado: error de compilación (`Spacing` no tiene el miembro `s2`).

- [ ] **Paso 3: Implementar**

```swift
import CoreGraphics

/// v2 spacing scale in points (redesign spec §4.3). Replaces
/// `DesignTokens.Spacing` in phase F9.
nonisolated enum Spacing {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}

/// v2 corner radii (redesign spec §4.4). Capsules use `Capsule()`.
/// Replaces `DesignTokens.Radius` in phase F9.
nonisolated enum Radius {
    /// A/M/D badges, kbd.
    static let badge: CGFloat = 4
    /// Ref chips.
    static let chip: CGFloat = 5
    /// Small buttons and inline segments.
    static let controlSmall: CGFloat = 6
    /// List row selection.
    static let row: CGFloat = 7
    /// Buttons, fields.
    static let control: CGFloat = 8
    /// Cards, repo tile, content pane corner.
    static let card: CGFloat = 12
    /// HUDs, popovers, toasts.
    static let popover: CGFloat = 14
    /// Glass sidebar, command palette.
    static let panel: CGFloat = 18
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `SpacingTests`. Resultado esperado: 2 tests en verde.

- [ ] **Paso 5: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/Spacing.swift gitForgeTests/DesignSystem/Theme/V2/SpacingTests.swift
git commit -m "feat: add v2 spacing and radius scales"
```

---

### Tarea 6: Densidad v2, métricas y fin de `comfy`

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/GraphMetrics.swift`
- Crear: `gitForge/DesignSystem/Theme/V2/DensityMetrics.swift`
- Modificar: `gitForge/DesignSystem/Theme/Density.swift` (fichero entero)
- Modificar: `gitForge/DesignSystem/Theme/AppTheme.swift:54` (lectura de la densidad guardada)
- Test: `gitForgeTests/DesignSystem/Theme/V2/DensityTests.swift`

**Interfaces:**
- Produce:
  - `GraphMetrics.regular` y `.compact`, con `laneWidth`, `firstLaneX`, `edgeWidth`, `nodeRadius`, `nodeGap`, `headOuterRadius`, `headInnerRadius`, `stashSize`, `worktreeRadius`, `selectHaloOutset`, `selectHaloOpacity`, `hoverRingOutset`, `hoverRingWidth`, `hoverRingOpacity` y `chipHeight`.
  - `DensityMetrics.regular` y `.compact`, con `rowList`, `rowSidebar`, `rowBranch`, `rowFile`, `rowHeader`, `diffLine`, `toolbarControl`, `toolbarInner`, `buttonRegular`, `buttonLarge`, `buttonSmall`, `fieldHeight`, `sidebarWidth`, `inspectorWidth` y `graph: GraphMetrics`.
  - `Density.resolve(_ raw: String?) -> Density` y `Density.metrics: DensityMetrics`.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

/// `Density` is main-actor isolated (target default isolation), unlike the
/// `nonisolated` v2 types, so this suite runs on the main actor.
@Suite("Density v2")
@MainActor
struct DensityTests {

    @Test("Only compact and regular remain")
    func cases() {
        #expect(Density.allCases == [.compact, .regular])
    }

    @Test("Stored values resolve; comfy, empty and unknown fall back to regular",
          arguments: [("compact", Density.compact), ("regular", .regular), ("comfy", .regular), ("", .regular), ("huge", .regular)])
    func resolve(raw: String, expected: Density) {
        #expect(Density.resolve(raw) == expected)
    }

    @Test("Nothing stored resolves to regular")
    func resolveNil() {
        #expect(Density.resolve(nil) == .regular)
    }

    @Test("Metrics match the design sheet")
    func metrics() {
        #expect(Density.regular.metrics.rowList == 28)
        #expect(Density.compact.metrics.rowList == 22)
        #expect(Density.compact.metrics.diffLine == 17)
        #expect(Density.compact.metrics.buttonRegular == 24)
        #expect(Density.regular.metrics.inspectorWidth == 480)
        #expect(Density.regular.metrics.graph.laneWidth == 14)
        #expect(Density.compact.metrics.graph.nodeRadius == 3.75)
        #expect(Density.compact.metrics.graph.chipHeight == 16)
    }

    @Test("v1 values are untouched until the screens migrate")
    func legacyUnchanged() {
        #expect(Density.regular.rowHeight == 30)
        #expect(Density.compact.rowHeight == 26)
        #expect(Density.regular.monoFontSize == 12.5)
        #expect(Density.compact.monoFontSize == 11.5)
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `DensityTests`. Resultado esperado: error de compilación, `type 'Density' has no member 'resolve'`.

- [ ] **Paso 3: Implementar `GraphMetrics.swift`**

```swift
import CoreGraphics

/// Commit graph geometry per density (redesign spec §4.5). `nonisolated`
/// for the off-main-actor `Canvas` renderer.
nonisolated struct GraphMetrics: Equatable, Sendable {
    /// Distance between lane centres.
    let laneWidth: CGFloat
    /// Lane 0 centre from the column edge.
    let firstLaneX: CGFloat
    let edgeWidth: CGFloat
    /// Commit node (filled) and merge node (hollow ring).
    let nodeRadius: CGFloat
    /// Ring in bg.content separating a node from its edges.
    let nodeGap: CGFloat
    let headOuterRadius: CGFloat
    let headInnerRadius: CGFloat
    /// Dashed square, corner radius 2.
    let stashSize: CGFloat
    /// Hollow dashed circle.
    let worktreeRadius: CGFloat
    let selectHaloOutset: CGFloat
    let selectHaloOpacity: Double
    let hoverRingOutset: CGFloat
    let hoverRingWidth: CGFloat
    let hoverRingOpacity: Double
    /// Ref chips in the description column.
    let chipHeight: CGFloat

    static let regular = GraphMetrics(
        laneWidth: 14, firstLaneX: 14, edgeWidth: 2, nodeRadius: 4.5, nodeGap: 2,
        headOuterRadius: 7.5, headInnerRadius: 3.5, stashSize: 9, worktreeRadius: 4.5,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 18
    )

    static let compact = GraphMetrics(
        laneWidth: 12, firstLaneX: 12, edgeWidth: 1.75, nodeRadius: 3.75, nodeGap: 2,
        headOuterRadius: 6.75, headInnerRadius: 2.75, stashSize: 7.5, worktreeRadius: 3.75,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 16
    )
}
```

- [ ] **Paso 4: Implementar `DensityMetrics.swift`**

```swift
import CoreGraphics

/// Row heights and fixed widths per density (redesign spec §4.6).
nonisolated struct DensityMetrics: Equatable, Sendable {
    let rowList: CGFloat
    let rowSidebar: CGFloat
    let rowBranch: CGFloat
    let rowFile: CGFloat
    let rowHeader: CGFloat
    let diffLine: CGFloat
    let toolbarControl: CGFloat
    let toolbarInner: CGFloat
    let buttonRegular: CGFloat
    let buttonLarge: CGFloat
    let buttonSmall: CGFloat
    let fieldHeight: CGFloat
    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    let graph: GraphMetrics

    static let regular = DensityMetrics(
        rowList: 28, rowSidebar: 28, rowBranch: 26, rowFile: 24, rowHeader: 28, diffLine: 19,
        toolbarControl: 34, toolbarInner: 28, buttonRegular: 28, buttonLarge: 32, buttonSmall: 22,
        fieldHeight: 32, sidebarWidth: 240, inspectorWidth: 480, graph: .regular
    )

    static let compact = DensityMetrics(
        rowList: 22, rowSidebar: 24, rowBranch: 22, rowFile: 20, rowHeader: 24, diffLine: 17,
        toolbarControl: 34, toolbarInner: 28, buttonRegular: 24, buttonLarge: 32, buttonSmall: 22,
        fieldHeight: 28, sidebarWidth: 240, inspectorWidth: 480, graph: .compact
    )
}
```

- [ ] **Paso 5: Reescribir `Density.swift`**

```swift
import SwiftUI

enum Density: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Reads a stored value. `comfy` (dropped in the v2 redesign) and anything
    /// unknown fall back to `.regular`.
    static func resolve(_ raw: String?) -> Density {
        raw.flatMap(Density.init(rawValue:)) ?? .regular
    }

    /// v2 row heights, widths and graph geometry.
    var metrics: DensityMetrics {
        switch self {
        case .compact: .compact
        case .regular: .regular
        }
    }

    /// v1 row height for the commit graph table. Removed in phase F9.
    var rowHeight: CGFloat {
        switch self {
        case .compact: 26
        case .regular: 30
        }
    }

    /// v1 monospace size. Removed in phase F9.
    var monoFontSize: CGFloat {
        switch self {
        case .compact: 11.5
        case .regular: 12.5
        }
    }
}
```

- [ ] **Paso 6: Leer la densidad guardada con `resolve`**

En `AppTheme.swift`, sustituir:

```swift
        let savedDensity = UserDefaults.standard.string(forKey: Keys.density).flatMap(Density.init(rawValue:)) ?? .regular
```

por:

```swift
        let savedDensity = Density.resolve(UserDefaults.standard.string(forKey: Keys.density))
```

- [ ] **Paso 7: Ejecutar y comprobar que pasa**

Ejecutar la suite `DensityTests`. Resultado esperado: todos en verde.

- [ ] **Paso 8: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/GraphMetrics.swift gitForge/DesignSystem/Theme/V2/DensityMetrics.swift gitForge/DesignSystem/Theme/Density.swift gitForge/DesignSystem/Theme/AppTheme.swift gitForgeTests/DesignSystem/Theme/V2/DensityTests.swift
git commit -m "feat: add v2 density metrics and drop the comfy density"
```

---

### Tarea 7: `LaneColors`

**Ficheros:**
- Crear: `gitForge/DesignSystem/Theme/V2/LaneColors.swift`
- Test: `gitForgeTests/DesignSystem/Theme/V2/LaneColorsTests.swift`

**Interfaces:**
- Consume: `AccentSwatch.swatch` (Tarea 2), `ColorMath.hueDistance` y `ColorMath.components` (Tarea 1).
- Produce:
  - `LaneColors.Lane` (`.lane0` … `.lane5`) y `LaneColors.Assignment` (`.accent`, `.lane(Lane)`).
  - `hashPool(accent:) -> [Lane]`
  - `assignment(branchId:priorityRank:isHead:accent:) -> Assignment`
  - `color(_:dark:accent:) -> Color`
  - `stash(dark:) -> Color`
  - `hex(_:dark:) -> UInt32`
  - `priorityRank` tiene el mismo significado que en `GraphPalette.color(branchId:priorityRank:)`: 0 es `main`/`master` y 1 es `develop`.

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("LaneColors")
struct LaneColorsTests {

    @Test("HEAD takes the accent, even when it is main")
    func headWins() {
        #expect(LaneColors.assignment(branchId: 7, priorityRank: nil, isHead: true, accent: .violet) == .accent)
        #expect(LaneColors.assignment(branchId: 0, priorityRank: 0, isHead: true, accent: .violet) == .accent)
    }

    @Test("Trunks are pinned: main to lane 0, develop to lane 3")
    func trunks() {
        #expect(LaneColors.assignment(branchId: 9, priorityRank: 0, isHead: false, accent: .violet) == .lane(.lane0))
        #expect(LaneColors.assignment(branchId: 9, priorityRank: 1, isHead: false, accent: .violet) == .lane(.lane3))
    }

    @Test("A pinned trunk keeps its lane even when the accent skips it")
    func trunkBeatsSkip() {
        #expect(LaneColors.assignment(branchId: 1, priorityRank: 0, isHead: false, accent: .blue) == .lane(.lane0))
    }

    @Test("The pool drops lanes near the accent's hue",
          arguments: [(AccentSwatch.blue, LaneColors.Lane.lane0), (.coral, .lane2), (.green, .lane4)])
    func skipsNearAccent(accent: AccentSwatch, skipped: LaneColors.Lane) {
        #expect(!LaneColors.hashPool(accent: accent).contains(skipped))
    }

    @Test("Hashed branches never take lane 1 or a lane within 30° of the accent", arguments: AccentSwatch.allCases)
    func hashedLanes(accent: AccentSwatch) {
        for id in -50..<200 {
            guard case .lane(let lane) = LaneColors.assignment(branchId: id, priorityRank: nil, isHead: false, accent: accent) else {
                Issue.record("branch \(id) got the accent"); return
            }
            #expect(lane != .lane1)
            #expect(ColorMath.hueDistance(LaneColors.hex(lane, dark: true), accent.swatch) >= 30)
        }
    }

    @Test("Assignment is stable and survives extreme ids")
    func stable() {
        let a = LaneColors.assignment(branchId: 42, priorityRank: nil, isHead: false, accent: .violet)
        #expect(a == LaneColors.assignment(branchId: 42, priorityRank: nil, isHead: false, accent: .violet))
        _ = LaneColors.assignment(branchId: .min, priorityRank: nil, isHead: false, accent: .violet)
        _ = LaneColors.assignment(branchId: .max, priorityRank: 2, isHead: false, accent: .blue)
    }

    @Test("Lane colours follow the theme")
    func themed() {
        #expect(LaneColors.hex(.lane0, dark: true) == 0x5AA9FF)
        #expect(LaneColors.hex(.lane0, dark: false) == 0x2F86EA)
        #expect(LaneColors.hex(.lane5, dark: false) == 0x8E4FD0)
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `LaneColorsTests`. Resultado esperado: error de compilación, `cannot find 'LaneColors' in scope`.

- [ ] **Paso 3: Implementar**

```swift
import SwiftUI

/// v2 commit-graph lane colours (redesign spec §4.5). Theme-aware, unlike
/// the v1 `GraphPalette`, and the HEAD branch always takes the accent.
/// `nonisolated` because the `Canvas` renderer runs off the main actor.
nonisolated enum LaneColors {
    enum Lane: Int, CaseIterable, Sendable {
        case lane0, lane1, lane2, lane3, lane4, lane5
    }

    enum Assignment: Equatable, Sendable {
        case accent
        case lane(Lane)
    }

    /// Lanes a hashed (non-HEAD, non-trunk) branch may take. Lane 1 is
    /// reserved for HEAD, and any lane within 30° of the accent's hue is
    /// skipped so no other branch reads as HEAD.
    static func hashPool(accent: AccentSwatch) -> [Lane] {
        [Lane.lane0, .lane2, .lane3, .lane4, .lane5].filter {
            ColorMath.hueDistance(hex($0, dark: true), accent.swatch) >= 30
        }
    }

    /// - Parameter priorityRank: trunk rank from the layout, as in
    ///   `GraphPalette.color(branchId:priorityRank:)`: 0 main/master, 1 develop.
    static func assignment(branchId: Int, priorityRank: Int?, isHead: Bool, accent: AccentSwatch) -> Assignment {
        if isHead { return .accent }
        switch priorityRank {
        case 0: return .lane(.lane0)
        case 1: return .lane(.lane3)
        default:
            let pool = hashPool(accent: accent)
            let index = ((branchId % pool.count) + pool.count) % pool.count
            return .lane(pool[index])
        }
    }

    static func color(_ assignment: Assignment, dark: Bool, accent: Color) -> Color {
        switch assignment {
        case .accent: accent
        case .lane(let lane): rgb(hex(lane, dark: dark))
        }
    }

    static func stash(dark: Bool) -> Color {
        rgb(dark ? 0x8E8E99 : 0x9A9AA6)
    }

    static func hex(_ lane: Lane, dark: Bool) -> UInt32 {
        switch lane {
        case .lane0: dark ? 0x5AA9FF : 0x2F86EA
        // Violet reference only: HEAD normally resolves through `.accent`.
        case .lane1: dark ? 0xA08CFF : 0x5B3DF5
        case .lane2: dark ? 0xF0729E : 0xD6457F
        case .lane3: dark ? 0xE8B04B : 0xC98A12
        case .lane4: dark ? 0x3FC4AE : 0x0F9A85
        case .lane5: dark ? 0xC792EA : 0x8E4FD0
        }
    }

    /// `Color(hex:)` is main-actor isolated; this stays callable from the renderer.
    private static func rgb(_ hex: UInt32) -> Color {
        let c = ColorMath.components(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `LaneColorsTests`. Resultado esperado: todos en verde.

- [ ] **Paso 5: Commit**

```bash
git add gitForge/DesignSystem/Theme/V2/LaneColors.swift gitForgeTests/DesignSystem/Theme/V2/LaneColorsTests.swift
git commit -m "feat: add v2 theme-aware lane colours"
```

---

### Tarea 8: Verificación de la fase y PR

**Ficheros:**
- Modificar: `design/redesign-v2/spec.md` (ya actualizada en la planificación: `theme.colors` y símbolos en F2). Se incluye en el PR.
- Añadir: este plan.

- [ ] **Paso 1: Ejecutar la suite completa**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
```

Resultado esperado: todos los tests en verde, incluidos los existentes `TypographyScaleTests` y `PaletteContrastTests`, y ninguna línea `warning:`.

- [ ] **Paso 2: Comprobar que no hay cambios visuales**

Arrancar la app (`/run` o Xcode). En Settings › Appearance, el selector Density muestra solo Compact y Regular. El resto de pantallas se ven exactamente igual que en `main`, porque no se ha tocado ninguna vista.

- [ ] **Paso 3: Commit de la documentación**

```bash
git add design/redesign-v2/spec.md design/redesign-v2/plans/F0-fundamentos.md
git commit -m "docs: add visual redesign v2 spec and F0 plan"
```

- [ ] **Paso 4: Parar y pedir aprobación para hacer push y abrir el PR**

Informar a Alvaro con el resumen de commits y el resultado de los tests. **No hacer push sin su OK explícito.** Con el OK:

```bash
git push -u origin feat/redesign-f0-foundations
gh pr create --title "feat: redesign v2 foundations (F0)" --body "$(cat <<'EOF'
## Summary
- v2 design tokens alongside v1: GFColors (4 variants), AccentSwatch, TypeRole + textRole, Spacing/Radius, DensityMetrics/GraphMetrics, LaneColors
- AppTheme exposes `colors` next to `palette`
- Drops the `comfy` density (stored value resolves to regular)
- Spec and F0 plan under design/redesign-v2/

No screen uses the new tokens yet; phases F1-F8 migrate them, F9 removes v1.

## Test plan
- [ ] Full suite green, 0 warnings
- [ ] Settings › Appearance shows Compact / Regular only
- [ ] No visual change elsewhere

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

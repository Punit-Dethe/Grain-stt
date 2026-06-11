// ConsoleTheme.qml — shared light/dark palette for the Quick Panel.
//
// A SINGLE instance lives in ConsoleWindow and is injected into every module
// via `property var theme`. Rather than hard-swapping colours, every colour is
// interpolated against an animated driver `t` (0 = light, 1 = dark). Because
// each colour binding reads `t`, flipping `isDark` animates `t` once and the
// ENTIRE panel — surfaces and text alike — crossfades in perfect sync. This is
// both smoother and far cheaper than putting a Behavior on every element.
//
// Visual model: in LIGHT mode outer module cards are dark charcoal, text is
// warm off-white; in DARK mode outer cards flip to cream/beige, text flips to
// charcoal. The inner content wells and window background invert in the
// opposite direction. Colour roles are semantic — matching a new reference
// only requires editing the endpoint values here.
import QtQuick 2.15

QtObject {
    id: theme

    // Public switch. Flipping this animates `t`.
    property bool isDark: false

    // Animated 0→1 driver. Everything below interpolates against it.
    property real t: isDark ? 1.0 : 0.0
    Behavior on t { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }

    // ── interpolation helpers ───────────────────────────────────────────
    // Linear blend between two colours (strings or color objects) by `t`.
    function mix(a, b) {
        var c1 = (typeof a === "string") ? Qt.color(a) : a
        var c2 = (typeof b === "string") ? Qt.color(b) : b
        return Qt.rgba(c1.r + (c2.r - c1.r) * t,
                       c1.g + (c2.g - c1.g) * t,
                       c1.b + (c2.b - c1.b) * t,
                       c1.a + (c2.a - c1.a) * t)
    }

    // Ink (text / lines) sitting on the INNER well or the window background:
    //   light → near-black ink, dark → warm off-white ink.
    function ink(a) {
        return mix(Qt.rgba(0.078, 0.075, 0.071, a), Qt.rgba(0.925, 0.898, 0.855, a))
    }
    // Ink sitting on the OUTER card — light-mode outer card is dark charcoal so
    // ink is warm off-white; dark-mode outer card is cream so ink flips to
    // charcoal. Inverse direction of ink().
    function inkOnOuter(a) {
        return mix(Qt.rgba(0.925, 0.898, 0.855, a), Qt.rgba(0.078, 0.075, 0.071, a))
    }
    // Neutral fill / border tint that flips black→white between modes (subtle
    // dark tint on a light well, subtle light tint on a dark well).
    function fill(a) { return mix(Qt.rgba(0, 0, 0, a), Qt.rgba(1, 1, 1, a)) }
    function line(a) { return mix(Qt.rgba(0, 0, 0, a), Qt.rgba(1, 1, 1, a)) }

    // ── window + header ─────────────────────────────────────────────────
    readonly property color windowBg:         mix("#ECE5DA", "#181716")
    readonly property color brandBadgeBg:      mix("#141312", "#ECE5DA")
    readonly property color brandBadgeText:    mix("#ECE5DA", "#141312")
    readonly property color windowCtrlBoxBg:   mix("#DDD5C8", Qt.rgba(1, 1, 1, 0.06))

    // ── module OUTER card — dark charcoal in light mode, cream in dark mode ─
    readonly property color cardOuter:         mix("#141312", "#ECE5DA")
    readonly property color cardOuterBorder:   mix(Qt.rgba(1, 1, 1, 0.06), Qt.rgba(0, 0, 0, 0.08))
    readonly property color cardOuterTitle:    mix(Qt.rgba(0.925, 0.898, 0.855, 1.0), Qt.rgba(0.078, 0.075, 0.071, 1.0))

    // ── module INNER well (the content pocket) — cream → dark ───────────
    readonly property color cardInner:         mix("#DDD5C8", "#0e0d0c")
    readonly property color cardInnerBorder:   mix(Qt.rgba(0, 0, 0, 0.06), Qt.rgba(1, 1, 1, 0.06))
    readonly property color cardInnerTopShade: mix(Qt.rgba(0, 0, 0, 0.08), Qt.rgba(0, 0, 0, 0.30))

    // ── inputs / dropdowns / controls ───────────────────────────────────
    readonly property color inputBg:           mix("#ECE5DA", "#201d1a")
    readonly property color inputText:         mix("#141312", "#ECE5DA")
    readonly property color dialKnob:          mix("#9e9587", "#4a443b")
    readonly property color toggleTrack:       mix("#000000", "#46413a")

    // ── jack housing plate (the patcher) ────────────────────────────────
    readonly property color jackHousingTop:    mix("#e5decb", "#211e1a")
    readonly property color jackHousingBottom: mix("#c7bca7", "#14110e")

    // ── misc ────────────────────────────────────────────────────────────
    readonly property color historyFade:       mix("#D2C9BB", "#0e0d0c")
}

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "MediaModel.js" as MediaModel

BarWidget {
  id: root
  moduleName: "omarchy.media"

  // The shell keys its service singletons by manifest id and does NOT resolve
  // clonedFrom for serviceFor() the way it does for summon/call -- so the
  // upstream `firstPartyServiceFor("omarchy.media")` returns null in any clone
  // (the built-in is disabled, so its service is never mounted). The bar host
  // overwrites moduleName with this widget's layout entry id, which is exactly
  // the id our own service is registered under; the literals after it are
  // fallbacks for a renamed entry or a switch back to the built-in.
  // Every label that renders MPRIS metadata goes through this.
  //
  // The strings are not ours: browsers forward the MediaSession API straight
  // through, so a web page picks them. PlainText is the guard -- left on the
  // AutoText default, Qt sniffs each string with Qt.mightBeRichText() and
  // renders anything HTML-shaped as markup, which would let a page restyle the
  // bar or blow a label's height past the slot the bar sized for it. Carrying
  // it here makes it structural: a label added later cannot forget it.
  // How long a tooltip stays up once it has appeared. Both tooltip systems in
  // play keep a tip on screen for as long as the pointer rests on the control
  // -- sweeping the transport row therefore drags a tooltip along with the
  // cursor, and it reads as one that will not go away. The text is a reminder
  // and a hotkey hint, not a label: show it for a beat, then drop it. Moving
  // to another control starts a fresh beat.
  readonly property int tooltipHold: 1000

  // Cover-art decode caps.
  //
  // trackArtUrl is not ours. A web page sets it through the MediaSession API
  // and the browser forwards it verbatim, so the bytes behind it are chosen by
  // whoever wrote the page -- and this shell runs for weeks.
  //
  // BOTH axes are capped, as a bounding box. Qt scales the source down to fit
  // inside the box and preserves its aspect ratio while doing so, so the box
  // costs nothing in fidelity. Capping a single axis does NOT bound the decode:
  // Qt only ever scales an image DOWN, so a source already shorter than the cap
  // is left entirely alone and its width stays whatever the attacker chose. A
  // 120000x200 PNG of flat colour is 69KB on the wire and decodes to 92MB of
  // RGBA -- measured, not theorised. With the box it decodes to nothing.
  //
  // The frame reads its aspect ratio off implicitWidth/implicitHeight -- the
  // dimensions of the pixmap Qt actually produced -- never off sourceSize,
  // which reads back as the box we asked for rather than anything about the
  // image.
  readonly property int artDecodeSize: Math.round(Style.space(134) * 2)
  readonly property int barArtDecodeSize: Math.round(artSize * 2)

  // Button with a tooltip that gives up after tooltipHold. Button renders its
  // own tooltip bound to its `containsMouse`, so the only lever from out here
  // is the text itself: blank it once the beat is over, restore it when the
  // pointer arrives again.
  component TipButton: Button {
    id: tipButton
    property string tipText: ""
    property bool tipExpired: false

    tooltipText: tipButton.tipExpired ? "" : tipButton.tipText

    onHotChanged: {
      tipExpired = false
      if (tipButton.hot) tipTimer.restart()
      else tipTimer.stop()
    }

    Timer {
      id: tipTimer
      interval: root.tooltipHold
      onTriggered: tipButton.tipExpired = true
    }
  }

  component MetaText: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  readonly property var mediaService: (bar && bar.shell)
    ? (bar.shell.serviceFor(root.moduleName)
       || bar.shell.serviceFor("ajkulundu.mediaplusplus")
       || bar.shell.serviceFor("omarchy.media"))
    : null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  // Bar thumbnail edge. Sized off the bar so it tracks a taller or shorter
  // bar instead of being pinned to one pixel count.
  readonly property real artSize: Math.round(barSize * 0.76)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  // ------------------------------------------------------------- media++
  readonly property bool isVideo: mediaService ? mediaService.isVideo : false
  readonly property real trackPosition: mediaService ? mediaService.trackPosition : 0
  readonly property real trackLength: mediaService ? mediaService.trackLength : 0
  readonly property bool hasLength: trackLength > 0
  readonly property bool canSeek: mediaService ? mediaService.canSeek : false
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""

  readonly property bool volumeSupported: mediaService ? mediaService.volumeSupported : false
  readonly property real volumeLevel: mediaService ? mediaService.volume : 0
  readonly property bool canRaise: mediaService ? mediaService.canRaise : false

  // Seek step, in seconds. Restricted to the four values Material ships a
  // numbered icon for, so the button always shows the number it actually
  // seeks; anything else in the config snaps to the nearest of them.
  readonly property var seekSteps: [5, 10, 15, 30]
  readonly property int seekStep: {
    var want = Number(setting("seekStep", 10))
    if (!isFinite(want)) return 10
    var best = seekSteps[0]
    for (var i = 1; i < seekSteps.length; i++)
      if (Math.abs(seekSteps[i] - want) < Math.abs(best - want)) best = seekSteps[i]
    return best
  }
  readonly property string rewindGlyph: seekStep === 5 ? "󱇹"
    : seekStep === 15 ? "󰴫" : seekStep === 30 ? "󰴬" : "󰴪"
  readonly property string forwardGlyph: seekStep === 5 ? "󱇸"
    : seekStep === 15 ? "󰵲" : seekStep === 30 ? "󰵳" : "󰵱"

  readonly property bool shuffleSupported: mediaService ? mediaService.shuffleSupported : false
  readonly property bool shuffleOn: mediaService ? mediaService.shuffleOn : false
  readonly property bool loopSupported: mediaService ? mediaService.loopSupported : false
  readonly property string loopLabel: mediaService ? mediaService.loopLabel : "Repeat off"

  // Secondary text colour, valid in both light and dark themes.
  //
  // Upstream (and every stock panel: bluetooth, weather, tailscale, Dropdown)
  // dims secondary text with Qt.darker(foreground, n). That only holds on a
  // dark theme. On a light theme the foreground is already near-black --
  // Flexoki Light is #100F0F -- so darkening it RAISES contrast, and the
  // "muted" album/artist/time labels end up more prominent than the title they
  // sit beneath. The hierarchy inverts exactly where it matters most.
  //
  // Mixing the foreground toward the surface it is drawn on always moves away
  // from the text colour, whichever direction that is, so a larger amount is
  // always fainter in both modes. Alpha is taken from the foreground so a
  // translucent popup background cannot bleed transparency into the text.
  function mutedText(amount) {
    var fg = bar ? bar.foreground : Color.foreground
    var bg = Color.popups.background
    return Qt.rgba(fg.r + (bg.r - fg.r) * amount,
                   fg.g + (bg.g - fg.g) * amount,
                   fg.b + (bg.b - fg.b) * amount,
                   fg.a)
  }

  // Icon for the app a player belongs to.
  //
  // Guessing an icon name from the player does not work: MPRIS desktopEntry
  // is often empty (Brave leaves it blank) and the identity rarely matches
  // the icon name (Brave's identity is "Brave", its icon is "brave-desktop").
  // So resolve through the desktop entry database instead and read the icon
  // off the entry -- id first, then the identity as a name match.
  function appIconFor(player) {
    if (!player) return ""

    var entry = null
    var id = String(player.desktopEntry || "")
    if (id) entry = DesktopEntries.heuristicLookup(id)

    var identity = String(player.identity || "").toLowerCase()
    if (!entry && identity) entry = DesktopEntries.heuristicLookup(identity)

    if (!entry && identity) {
      var list = DesktopEntries.applications ? DesktopEntries.applications.values : []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].name || "").toLowerCase() === identity) {
          entry = list[i]
          break
        }
      }
    }

    if (entry && entry.icon) {
      var themed = Quickshell.iconPath(entry.icon, true)
      if (themed) return themed
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Hotkeys, live only while the popup is open.
  //
  //   space  play/pause      b  back 10s      f  forward 10s
  //   n      next track      p  previous      v  square <-> vinyl
  //   m      cycle section   y  progress style s  settings
  //   esc    close
  //
  // Matched on event.text rather than Qt.Key_* so the letters follow the
  // active keyboard layout instead of hard-coding a QWERTY scancode.
  function handleKey(event) {
    if (!root.popupOpen) return
    var svc = root.mediaService
    var text = String(event.text || "").toLowerCase()

    // Escape works with or without a service behind it.
    if (event.key === Qt.Key_Escape) {
      root.close()
      event.accepted = true
      return
    }
    if (!svc) return

    // Continuous adjustments come first, because these are the only keys that
    // should act on auto-repeat: holding f scrubs forward, holding Up ramps
    // the volume. Feedback is suppressed throughout -- the popup is on screen
    // and already shows the seek bar and the volume slider, so an OSD over it
    // is noise rather than feedback.
    if (text === "b" || event.key === Qt.Key_Left) {
      svc.seekBy(-root.seekStep, false)
      event.accepted = true
      return
    }
    if (text === "f" || event.key === Qt.Key_Right) {
      svc.seekBy(root.seekStep, false)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) {
      svc.adjustVolume(0.05, false)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down) {
      svc.adjustVolume(-0.05, false)
      event.accepted = true
      return
    }

    // Everything below is a discrete action. A held space would machine-gun
    // play/pause and a held n would skip a dozen tracks, so repeats stop here
    // -- accepted, so they are swallowed rather than passed on.
    if (event.isAutoRepeat) {
      event.accepted = true
      return
    }

    var handled = true

    if (event.key === Qt.Key_Space) {
      svc.runAction("playPause", false)
    } else if (text === "n") {
      svc.runAction("next", false)
    } else if (text === "p") {
      svc.runAction("previous", false)
    } else if (text === "x") {
      svc.toggleShuffle(false)
    } else if (text === "r") {
      svc.cycleLoop(false)
    } else if (text === "o") {
      root.raisePlayer()
    } else if (text === "[") {
      svc.switchSource(-1, false, false)
    } else if (text === "]") {
      svc.switchSource(1, false, false)
    } else if (text === "m") {
      var order = ["left", "center", "right"]
      var at = order.indexOf(root.barSection)
      root.setBarSection(order[(at + 1) % order.length])
    } else if (text === "y") {
      // indexOf returns -1 for a value written by an older version, and -1 + 1
      // lands on the first style, which is the right place to restart from.
      var styles = root.progressStyles
      var si = styles.indexOf(root.progressAnimation)
      root.setProgressAnimation(styles[(si + 1) % styles.length])
    } else if (text === "v") {
      root.setArtworkStyle(root.vinylArtwork ? "square" : "vinyl")
    } else if (text === "s") {
      root.settingsOpen = !root.settingsOpen
    } else {
      handled = false
    }

    event.accepted = handled
  }

  // Progress bar animation. The seek bar's value is fed from a local
  // displayPosition rather than straight from the service, so the curve the
  // fill travels on is ours to choose; PanelSlider's own 140ms smoothing
  // rides on top of whichever we pick.
  readonly property var progressStyles: ["default", "wiggle", "pacman"]
  readonly property string progressAnimation: {
    var stored = String(setting("progressAnimation", "default"))
    // "stripes" was the barber-pole style up to v1.1.1, which pacman replaced.
    // Map it rather than letting an existing config fall silently back to the
    // plain bar -- the user picked a drawn style, so give them one.
    if (stored === "stripes") return "pacman"
    return progressStyles.indexOf(stored) === -1 ? "default" : stored
  }
  readonly property bool wiggleProgress: progressAnimation === "wiggle"
  readonly property bool pacmanProgress: progressAnimation === "pacman"
  // Both drawn styles share one bar body and one Canvas, differing only in
  // what that Canvas paints. Pacman also takes over the remaining track and
  // the stop dot, because its pellets ARE the track.
  readonly property bool styledProgress: wiggleProgress || pacmanProgress

  readonly property int progressDuration: styledProgress ? 300 : 140
  readonly property int progressEasing: styledProgress ? Easing.Bezier : Easing.OutCubic

  // Material's standard curve, cubic-bezier(0.4, 0, 0.2, 1). QML wants the
  // two control points plus the (1,1) endpoint.
  readonly property var progressBezier: styledProgress
    ? [0.4, 0.0, 0.2, 1.0, 1.0, 1.0] : []

  property real displayPosition: 0
  property bool progressStepping: true

  // Ordinary playback advances the position by about a second at a time; a
  // seek or a track change moves it by a lot. Animating the big jumps would
  // send the fill gliding across the whole track, so only the small steps
  // are animated and anything larger snaps.
  onTrackPositionChanged: {
    progressStepping = Math.abs(trackPosition - displayPosition) < 2.5
    displayPosition = trackPosition
  }

  Behavior on displayPosition {
    enabled: root.progressStepping
    NumberAnimation {
      duration: root.progressDuration
      easing.type: root.progressEasing
      easing.bezierCurve: root.progressBezier
    }
  }

  // Every per-widget setting is an inline field on this widget's own layout
  // entry, which the shell writes through updateEntryInline -- the same path
  // the clock uses when it cycles its format. Applied to `settings` locally
  // first so the popup reflects the change on the click itself rather than
  // after the config round-trip.
  function writeSetting(key, value) {
    root.preservePopup()

    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setProgressAnimation(style) {
    if (root.progressStyles.indexOf(style) === -1) return
    if (style === root.progressAnimation) return
    writeSetting("progressAnimation", style)
  }

  function formatTime(seconds) {
    return mediaService ? mediaService.formatTime(seconds) : "0:00"
  }

  property bool popupOpen: false
  property bool settingsOpen: false

  // Leaving the settings view open would mean the next summon lands on the
  // form rather than on what is playing, which is not what a media popup is
  // for. Reset whenever the popup closes, however it was closed.
  onPopupOpenChanged: {
    if (popupOpen) return
    settingsOpen = false
    dismissArmed = false
    leaveTimer.stop()
  }

  // Which bar section this widget currently sits in, read back from the live
  // shell config rather than cached locally -- the user can also move the
  // widget by dragging it on the bar or via `omarchy bar move`, and the form
  // has to show where it actually is, not where this popup last put it.
  readonly property string barSection: {
    var cfg = bar && bar.shell ? bar.shell.shellConfig : null
    var layout = cfg && cfg.bar ? cfg.bar.layout : null
    if (!layout) return "center"
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; i++) {
      var list = layout[sections[i]]
      if (!Array.isArray(list)) continue
      for (var j = 0; j < list.length; j++) {
        if (list[j] && String(list[j].id) === root.moduleName) return sections[i]
      }
    }
    return "center"
  }

  // Popup artwork presentation: "square" (default) or "vinyl".
  readonly property string artworkStyle: String(setting("artworkStyle", "square"))
  readonly property bool vinylArtwork: artworkStyle === "vinyl"

  function setArtworkStyle(style) {
    if (style !== "square" && style !== "vinyl") return
    if (style === root.artworkStyle) return
    writeSetting("artworkStyle", style)
  }

  // `omarchy bar move` owns the shell.json write and the relayout; going
  // through it keeps this popup from hand-editing the layout and racing the
  // shell's own config watcher.
  // Every setter below writes shell.json, and the bar rebuilds this widget's
  // slot when the config reloads -- which takes the popup with it. Changing a
  // setting from inside the popup would therefore shut the popup, so the
  // state is handed to the service first and picked up by the rebuilt widget.
  function preservePopup() {
    if (!root.popupOpen || !root.mediaService) return
    root.mediaService.restorePopup = true
    root.mediaService.restoreSettings = root.settingsOpen
  }

  // Consumed once, by the rebuilt widget, to put the popup back.
  function restorePopupIfRequested() {
    var svc = root.mediaService
    if (!svc || svc.restorePopup !== true) return
    svc.restorePopup = false
    root.settingsOpen = svc.restoreSettings === true
    svc.restoreSettings = false
    root.popupOpen = true
  }

  Component.onCompleted: Qt.callLater(root.restorePopupIfRequested)
  onMediaServiceChanged: Qt.callLater(root.restorePopupIfRequested)

  function setBarSection(section) {
    if (!bar || !section || section === root.barSection) return

    root.preservePopup()
    // Util.shellQuote, not bar.shellQuote. The bar README lists shellQuote
    // among the helpers a widget gets off `bar`, but Bar.qml never defines
    // it -- it lives on the qs.Commons Util singleton, which is what the
    // first-party widgets call. Going through `bar` threw a TypeError and
    // aborted this function before it ever ran the command, so picking a
    // section silently did nothing.
    bar.run("omarchy bar move " + Util.shellQuote(root.moduleName)
            + " --section " + Util.shellQuote(section))
  }

  function close() { popupOpen = false; settingsOpen = false }

  // Raising hands the compositor's keyboard focus to the player's own window,
  // which leaves the popup on screen with no way to type at it. Asking for the
  // player is also a statement that you are done with the popup, so close it.
  function raisePlayer() {
    if (!root.mediaService || !root.mediaService.raiseActivePlayer()) return false
    root.close()
    return true
  }

  // Shape contract for shell summon/hide/toggle routing: Bar.findPanelWidget
  // requires open(), close() and `opened` on the bar-widget root before it
  // will route to a widget at all. With these present,
  // `omarchy-shell shell toggle <plugin-id>` reaches this popup, and the bar
  // picks the instance on the focused monitor rather than opening one popup
  // per screen. Going through shell routing rather than a second IpcHandler
  // also avoids fighting the service for the single handler a target allows.
  // Guarded on hasMedia: the widget hides itself when nothing is playing, and
  // opening a popup anchored to a zero-size invisible item put a focus-taking
  // layer surface on screen with nothing to show in it.
  readonly property bool opened: popupOpen
  function open() { if (root.hasMedia) popupOpen = true }
  function toggle() { popupOpen = !popupOpen && root.hasMedia }
  // Fixed label width. The bar slot must not resize as tracks change -- a
  // widget that grows and shrinks with the title shoves every widget beside it
  // sideways on every track change. The label column is always this wide
  // whenever media is present, whether the text is short or long.
  readonly property real labelWidth: Style.space(Number(setting("labelWidth", 136)))

  // Carousel pace. scrollSpeed is a multiplier on the base 25ms-per-pixel
  // pace, so values below 1 are slower; it divides the duration, and the
  // lower clamp keeps a zero or negative setting from producing an infinite
  // duration that would freeze the label off-screen.
  readonly property real scrollSpeed: Math.max(0.05, Number(setting("scrollSpeed", 0.6)))
  readonly property int scrollPauseMs: Math.max(0, Math.round(Number(setting("scrollPause", 5)) * 1000))

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // Artwork stands where the play/pause glyph used to. The bar carries no
    // controls now -- it is a status readout, and every transport button lives
    // in the popup. Cropped square here because a 16:9 thumbnail letterboxed
    // into a bar-height slot is mostly empty space; the popup is where the
    // artwork's true aspect ratio is preserved.
    Item {
      id: glyph
      width: root.artSize
      height: root.artSize
      anchors.verticalCenter: parent.verticalCenter

      // Dimmed while paused. With the glyph gone this is the only play-state
      // cue left in the bar, and it reads without adding a control.
      opacity: root.activePlayer && root.activePlayer.isPlaying ? 1.0 : 0.5
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Image {
        id: barArt
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        // Cover art arrives at 600px+ and lands in a ~18px slot. Without an
        // explicit sourceSize the full-size image is decoded and then naively
        // downscaled, which aliases into noise at this size; decoding at 2x
        // the slot lets Qt filter properly and leaves headroom for scaling.
        sourceSize.width: root.barArtDecodeSize
        sourceSize.height: root.barArtDecodeSize
        source: root.artUrl
        visible: status === Image.Ready && root.artUrl !== ""
      }

      // Streams and local files often carry no cover at all; fall back to the
      // kind glyph rather than leaving a hole in the bar.
      Text {
        anchors.centerIn: parent
        visible: !barArt.visible
        text: root.isVideo ? "󰕧" : "󰝚"
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Item {
      id: scrollClip
      width: root.labelWidth
      // Tall enough for the text's own line box, not just the artwork.
      // This clip exists to bound horizontal scrolling; sizing it to the
      // artwork (18px) made it shorter than the label's line height and
      // clip:true then sliced the descenders off g/j/p/q/y. It only showed
      // on some tracks -- "Wizkid" has no descenders, "Flaxy" does -- which
      // made it look like a browser-specific fault rather than a height bug.
      height: Math.max(glyph.height, labelText.implicitHeight)
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      // Gap between the two copies of the label, so a looping title reads as
      // "... Joeboy    Baby · Joeboy ..." rather than running into itself.
      readonly property real gap: Style.space(32)
      readonly property bool needsScroll: labelText.implicitWidth > width

      // Carousel. Upstream scrolls one copy of the text from the right edge to
      // fully off the left, which leaves the label blank for most of each
      // cycle. Drawing the text twice and translating by exactly one
      // copy-plus-gap means that when the animation restarts, the second copy
      // sits precisely where the first began: the seam is invisible and text
      // is on screen continuously.
      Row {
        id: marquee
        spacing: scrollClip.gap
        anchors.verticalCenter: parent.verticalCenter

        property real scrollOffset: 0

        // Left-aligned while it fits, scrolling once it does not. x keeps a
        // real binding in both cases, so a stopped animation can never strand
        // the label outside the clip rectangle.
        x: scrollClip.needsScroll ? marquee.scrollOffset : 0

        MetaText {
          id: labelText
          text: root.title + (root.artist ? "  ·  " + root.artist : "")
          color: root.bar.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }

        MetaText {
          text: labelText.text
          visible: scrollClip.needsScroll
          color: labelText.color
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Scroll one full cycle, then hold so the title can actually be read
      // before it moves again. The pause comes first in the sequence so a
      // freshly changed track is legible immediately instead of sliding away
      // the moment it appears. Holding at the end of a cycle and holding at
      // the start are the same picture here: at offset -(copy + gap) the
      // second copy sits exactly where the first began.
      SequentialAnimation {
        id: scrollAnim
        running: scrollClip.needsScroll && !root.bar.vertical
        loops: Animation.Infinite

        PauseAnimation { duration: root.scrollPauseMs }

        NumberAnimation {
          target: marquee
          property: "scrollOffset"
          from: 0
          to: -(labelText.implicitWidth + scrollClip.gap)
          duration: Math.max(6000, (labelText.implicitWidth + scrollClip.gap) * 25) / root.scrollSpeed
          easing.type: Easing.Linear
        }
      }
    }
  }

  // The bar shows its tooltip 400ms after the pointer lands, then keeps it up
  // for as long as the pointer stays. Hand it back after the hold so resting
  // the cursor on the bar does not leave a tooltip parked over the desktop.
  Timer {
    id: barTipTimer
    interval: 400 + root.tooltipHold
    onTriggered: if (root.bar) root.bar.hideTooltip(root)
  }

  // The bar is a readout, not a control surface. A left click opens the popup
  // -- the same gesture the clock, audio and bluetooth widgets use -- and no
  // other button or wheel gesture does anything, so a stray scroll across the
  // bar can no longer skip a track.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton

    onClicked: {
      if (!root.activePlayer) return
      root.popupOpen = !root.popupOpen
    }
    onEntered: {
      if (!root.bar) return
      root.bar.showTooltip(root, root.hasMedia
        ? MediaModel.plainText(root.title + (root.artist ? " \u2014 " + root.artist : "")) : "")
      barTipTimer.restart()
    }
    onExited: {
      barTipTimer.stop()
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  // Dismissal follows the pointer, not the focus.
  //
  // The popup is a KeyboardPanel -- a full-screen layer surface -- so it owns
  // click-outside dismissal itself and there is no HyprlandFocusGrab to fight.
  // What remains is the courtesy close: nothing auto-closes until the pointer
  // has actually reached the popup, and after that, leaving it briefly closes
  // it. Opening by hotkey with the mouse elsewhere stays put until Esc, the
  // widget, or the hotkey.
  property bool dismissArmed: false

  Connections {
    target: popupHover
    function onHoveredChanged() {
      if (popupHover.hovered) {
        root.dismissArmed = true
        leaveTimer.stop()
      } else if (root.dismissArmed) {
        leaveTimer.restart()
      }
    }
  }

  Timer {
    id: leaveTimer
    // Enough to cross the gap back to the bar widget or overshoot an edge,
    // without the popup feeling like it is loitering.
    interval: 900
    onTriggered: if (!popupHover.hovered) root.close()
  }

  // KeyboardPanel, not PopupCard.
  //
  // PopupCard is an xdg popup anchored to the bar, and Bar.qml declares the
  // bar's layer surface keyboardFocus: None -- so no key ever reaches an xdg
  // popup. The previous workaround was a 1x1 click-through layer surface that
  // primed WlrKeyboardFocus.Exclusive and then settled on OnDemand. Measured,
  // that gave the hotkeys a 75ms life: Exclusive does win focus on map, but
  // OnDemand cannot HOLD it for a 1x1 surface with an empty input mask, so the
  // compositor handed focus straight back to whatever was underneath the
  // moment the prime timer fired. Keys pressed 40ms after opening worked; keys
  // pressed at 300ms went to the window below -- to the browser, which is why
  // space and f behaved like YouTube's own shortcuts instead of the popup's.
  //
  // KeyboardPanel is what the first-party panels use, and it works for the one
  // reason the 1x1 surface could not: it is FULL SCREEN. OnDemand keeps focus
  // on a surface the pointer is actually over, while still releasing
  // compositor-wide pointer hit-testing so clicks reach the bar and the
  // windows below. It also brings its own click-outside dismissal and the
  // popout coordination the bar expects.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // Layer-shell grants focus to the SURFACE, but Qt still needs an item
    // inside it holding active focus before Keys.onPressed fires.
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(240))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      // BeforeItem so the hotkeys win over any descendant that has taken
      // focus, rather than being swallowed by it.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      // Non-blocking and on top: it observes the pointer entering the popup
      // without taking hover away from the buttons underneath. Inside the
      // card, so the full-screen surface around it does not read as hovered.
      Item {
        anchors.fill: parent
        z: 100

        HoverHandler {
          id: popupHover
          blocking: false
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // -------------------------------------------------------------- header
        //
        // Gear sits top-right, in the column flow rather than floating over the
        // artwork -- a 16:9 thumbnail reaches the full content width, so an
        // overlaid button would sit on top of the picture.
        Item {
          width: parent.width
          height: gearButton.height

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.settingsOpen
            text: "Settings"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          TipButton {
            id: gearButton
            anchors.right: parent.right
            anchors.top: parent.top
            width: Style.space(26)
            height: Style.space(26)
            iconText: root.settingsOpen ? "󰝚" : "󰒓"
            foreground: root.bar.foreground
            opacity: root.settingsOpen ? 1.0 : 0.55
            tipText: root.settingsOpen ? "Close settings  (s)" : "Settings  (s)"
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }

        Column {
          id: playerView
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(10)

          // ------------------------------------------------------------- artwork
          //
          // The frame takes its shape from the artwork's own pixels rather than
          // from the metadata guess: a square album cover stays square, a 16:9
          // video thumbnail stays 16:9, and anything unusual is letterboxed
          // instead of cropped. mediaKind only picks the placeholder glyph, so a
          // wrong guess costs an icon, never a mangled image.
          Item {
            id: artFrame

            // Measured off the loaded pixmap, never off sourceSize: sourceSize
            // reads back as the bounding box we asked for, so using it reported
            // every cover as square and put the placeholder glyph over all of
            // them. implicitWidth/Height are the dimensions Qt actually
            // produced, and they carry the source's true ratio.
            readonly property bool ready: artImage.status === Image.Ready
              && artImage.implicitWidth > 0 && artImage.implicitHeight > 0

            // Clamped to ratios a cover plausibly has. The decode box already
            // bounds memory, but it cannot make a 400:1 banner a sensible
            // shape -- unclamped, that lands as a 240x1 sliver with the
            // metadata jammed under it. Anything past the clamp is letterboxed
            // by PreserveAspectFit instead, which is the honest way to show an
            // image that is not cover-shaped.
            readonly property real minAspect: 0.4
            readonly property real maxAspect: 2.5
            readonly property real rawAspect: ready
              ? artImage.implicitWidth / artImage.implicitHeight
              : (root.isVideo ? 16 / 9 : 1)
            readonly property real aspect: Math.min(maxAspect, Math.max(minAspect, rawAspect))
            readonly property real maxHeight: Style.space(134)

            visible: !root.vinylArtwork
            anchors.horizontalCenter: parent.horizontalCenter
            // `aspect` is already clamped to a sane range, so the old
            // Math.max(0.2, ...) guard against a divide-by-zero is redundant.
            height: visible ? Math.min(maxHeight, column.width / aspect) : 0
            width: visible ? Math.min(column.width, height * aspect) : 0

            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // Cursor position over the cover, normalised to -0.5..0.5 on each
            // axis. Drives both the tilt and where the light falls, so the two
            // read as one object turning under a fixed light rather than two
            // unrelated animations.
            readonly property real hoverX: artHover.hovered
              ? Math.max(-0.5, Math.min(0.5, artHover.point.position.x / Math.max(1, width) - 0.5)) : 0
            readonly property real hoverY: artHover.hovered
              ? Math.max(-0.5, Math.min(0.5, artHover.point.position.y / Math.max(1, height) - 0.5)) : 0
            readonly property bool lifted: artHover.hovered && ready

            Item {
              id: artTilt
              anchors.fill: parent

              // Small angles on purpose: without a perspective matrix an axis
              // rotation is an orthographic squash, which reads as a tilt only
              // while it stays shallow. Past roughly ten degrees it starts to
              // look like the cover is being flattened rather than turned.
              // One eased value drives the lift, so the Behavior actually has
              // something to animate. The previous `Behavior on scale` sat on
              // Item.scale, which nothing ever assigned -- the Scale transform
              // below uses xScale/yScale -- so the 1.03 pop snapped instead.
              property real liftScale: artFrame.lifted ? 1.03 : 1.0
              Behavior on liftScale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

              // Ease the tilt back to level on exit. Following the pointer is
              // meant to feel direct, so the curve is short enough not to lag
              // the cursor but long enough that letting go does not snap.
              property real tiltX: -artFrame.hoverY * 13
              property real tiltY: artFrame.hoverX * 13
              Behavior on tiltX { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
              Behavior on tiltY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

              transform: [
                Rotation {
                  origin.x: artTilt.width / 2
                  origin.y: artTilt.height / 2
                  axis { x: 1; y: 0; z: 0 }
                  angle: artTilt.tiltX
                },
                Rotation {
                  origin.x: artTilt.width / 2
                  origin.y: artTilt.height / 2
                  axis { x: 0; y: 1; z: 0 }
                  angle: artTilt.tiltY
                },
                Scale {
                  origin.x: artTilt.width / 2
                  origin.y: artTilt.height / 2
                  xScale: artTilt.liftScale
                  yScale: artTilt.liftScale
                }
              ]

              // The lift. Layered only while hovered so the effect node is not
              // kept alive for a cover nobody is pointing at. MultiEffect pads
              // its own bounds for the shadow, so it is not clipped by the item.
              layer.enabled: artFrame.lifted
              layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.7
                shadowVerticalOffset: Style.space(5)
                shadowOpacity: 0.5
                shadowColor: "black"
                brightness: 0.05
              }

            BorderSurface {
              anchors.fill: parent
              radius: Style.spacing.labelGap
              color: Style.normalFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
              clip: true

              Image {
                id: artImage
                anchors.fill: parent
                anchors.margins: Style.space(2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                // A bounding box on both axes, so no aspect ratio can escape
                // it. Constant rather than bound to the frame, whose width and
                // height animate: a decode per animation frame is exactly what
                // this cap exists to prevent.
                sourceSize.width: root.artDecodeSize
                sourceSize.height: root.artDecodeSize
                // Dropped while the vinyl is on screen. The source drives the
                // load, not visibility, so leaving it set kept a second full
                // decode of every cover alive behind the record.
                source: root.vinylArtwork ? "" : root.artUrl
                visible: artFrame.ready
              }

              Text {
                anchors.centerIn: parent
                visible: !artFrame.ready
                text: root.isVideo ? "󰕧" : "󰝚"
                color: root.mutedText(0.32)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
              }

              // The light. A soft diagonal band that sits under the cursor, so
              // moving across the cover sweeps the highlight with it. Inside the
              // clipping surface so it never spills past the rounded corners.
              Rectangle {
                id: sheen
                width: parent.width * 0.55
                height: parent.height * 2
                rotation: 18
                transformOrigin: Item.Center
                x: (artFrame.hoverX + 0.5) * parent.width - width / 2
                y: -parent.height / 2
                opacity: artFrame.lifted ? 1 : 0
                visible: opacity > 0

                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                  GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.17) }
                  GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }

                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
              }
            }
            }

            // HoverHandler rather than a hover-enabled MouseArea: it is the
            // purpose-built way to observe the pointer, and unlike a MouseArea
            // it cannot consume a click meant for anything layered beneath the
            // cover, whatever acceptedButtons is set to.
            HoverHandler {
              id: artHover
              cursorShape: root.canRaise ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            // Click the cover to bring the player's own window forward. MPRIS
            // Raise() is advisory -- plenty of players advertise it and then
            // do nothing -- so this is gated on canRaise and stays silent
            // either way rather than reporting a success it cannot verify.
            TapHandler {
              enabled: root.canRaise
              onTapped: root.raisePlayer()
            }

          }

          // --------------------------------------------------------- vinyl art
          //
          // Same artwork, presented as a record: the cover becomes the centre
          // label, masked to a circle, on a grooved disc that turns while the
          // track plays. Square remains the default because it shows the whole
          // cover; the vinyl crops to a circle by nature.
          Item {
            id: vinylFrame
            visible: root.vinylArtwork
            anchors.horizontalCenter: parent.horizontalCenter
            height: visible ? Math.min(Style.space(134), column.width) : 0
            width: height

            // A record is black, but a black disc on a near-black popup would be
            // invisible, so the disc is pitched against the surface it sits on:
            // lifted above a dark background, near-black on a light one. Same
            // reasoning as mutedText -- derive from the surface, never hardcode.
            readonly property color discColor: {
              var bg = Color.popups.background
              var lum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
              return lum < 0.5 ? Qt.rgba(0.16, 0.16, 0.17, 1) : Qt.rgba(0.08, 0.08, 0.09, 1)
            }
            // Ring around the spindle hole. The disc carries no groove lines --
            // the artwork fills it edge to edge and stays unbroken.
            readonly property color grooveDark: Qt.rgba(0, 0, 0, 0.32)

            Item {
              id: disc
              anchors.fill: parent

              // Paused, not stopped. Toggling `running` restarts the animation,
              // and a restart jumps straight back to `from: 0` -- so every
              // pause/resume snapped the record upright instead of picking up
              // where it left off. Holding it running and flipping `paused`
              // keeps the angle, so resuming continues from the exact frame it
              // stopped on. Easing and direction are pinned rather than left to
              // defaults: any curve other than linear would make the disc surge
              // and slow once per revolution.
              RotationAnimation on rotation {
                // Held running rather than stopped so the angle survives a
                // pause (see below), but paused whenever nothing is watching:
                // with the popup shut, or with square artwork selected, this
                // disc is not on screen and has no business ticking.
                running: true
                paused: !root.popupOpen || !root.vinylArtwork
                  || !(root.activePlayer && root.activePlayer.isPlaying)
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 18000
                direction: RotationAnimation.Clockwise
                easing.type: Easing.Linear
              }

              Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: vinylFrame.discColor
                border.width: 1
                border.color: Style.normalFillFor(root.bar.foreground, Color.accent)
                // A curved edge in motion shows its stair-stepping far more
                // than a static one; QML leaves this off by default.
                antialiasing: true
              }

              // Artwork fills the whole disc, masked to the full circle --
              // clip is rectangular in QML, so a radius alone will not round an
              // image. The disc colour still shows through when a track has no
              // cover, leaving a plain record rather than a hole.
              Item {
                id: discArt
                anchors.fill: parent

                // Only while the record is actually on screen. A layer is an
                // offscreen buffer the size of the item; left enabled, this
                // one and the mask below held two of them for a disc that is
                // not being drawn.
                layer.enabled: root.vinylArtwork
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: discMask
                  // A narrow spread around the threshold feathers the rim by a
                  // pixel. A hard cut reads as a jagged edge once the disc is
                  // turning, which is exactly where it is most visible.
                  maskThresholdMin: 0.48
                  maskSpreadAtMin: 0.08
                }

                Image {
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  smooth: true
                  mipmap: true
                  // Covers arrive around 600px and land in a ~155px disc. Left
                  // to scale the full-size decode every frame, the fine detail
                  // crawls and sparkles as the record turns; decoding near the
                  // drawn size lets Qt filter it once instead.
                  //
                  // A constant, not vinylFrame's size: the frame collapses to
                  // 0 when square artwork is selected, and a sourceSize of 0
                  // means "no cap", so hiding the record was what made it
                  // decode at full resolution.
                  sourceSize.width: root.artDecodeSize
                  sourceSize.height: root.artDecodeSize
                  source: root.vinylArtwork ? root.artUrl : ""
                  visible: status === Image.Ready && root.artUrl !== ""
                }
              }

              Item {
                id: discMask
                anchors.fill: parent
                visible: false
                layer.enabled: root.vinylArtwork

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: "black"
                  antialiasing: true
                }
              }

              // Spindle hole.
              Rectangle {
                anchors.centerIn: parent
                width: disc.width * 0.055
                height: width
                radius: width / 2
                color: Color.popups.background
                border.width: 1
                border.color: vinylFrame.grooveDark
                antialiasing: true
              }
            }
          }

          // ---------------------------------------------------------- track text
          Column {
            width: parent.width
            spacing: Style.space(2)

            MetaText {
              text: root.title || "Nothing playing"
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
            }

            MetaText {
              text: root.artist
              color: root.mutedText(0.26)
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: text !== ""
            }

            MetaText {
              text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
              color: root.mutedText(0.43)
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: text !== ""
            }
          }

          // ------------------------------------------------------------ seek bar
          //
          // Hidden entirely for players that report no length (most live streams),
          // rather than showing a bar that can never fill. While dragging, the
          // elapsed label follows the knob so you can see where you are landing.
          Item {
            id: seekBlock
            width: parent.width
            readonly property real barArea: root.styledProgress
              ? wiggleBar.height : seekSlider.implicitHeight
            height: barArea + timeRow.implicitHeight
            visible: root.hasLength

            PanelSlider {
              id: seekSlider
              bar: root.bar
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              minimum: 0
              maximum: Math.max(1, root.trackLength)
              step: 5
              value: root.displayPosition
              enabled: root.canSeek
              visible: !root.styledProgress
              opacity: root.canSeek ? 1.0 : 0.45
              onReleased: function(value) {
                if (root.mediaService) root.mediaService.seekToSeconds(value)
              }
            }

            // Material 3 Expressive progress indicator. Choosing "wiggle"
            // changes the shape as well as the curve: a wavy 4dp active
            // indicator, a 4dp gap before the remaining track, and the stop
            // indicator dot at the far end. PanelSlider cannot express any of
            // that -- its track, fill and knob are fixed internally -- so this
            // is a separate bar, shown instead of the slider, with its own
            // press/drag seeking.
            Item {
              id: wiggleBar
              visible: root.styledProgress
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: Style.space(18)
              opacity: root.canSeek ? 1.0 : 0.45

              readonly property real barHeight: Style.space(4)
              readonly property real gap: Style.space(4)
              readonly property real stopSize: Style.space(4)

              property bool dragging: false
              property real dragFraction: 0

              readonly property real fraction: dragging ? dragFraction
                : (root.trackLength > 0
                   ? Math.min(1, Math.max(0, root.displayPosition / root.trackLength)) : 0)
              readonly property real activeWidth: Math.round(fraction * width)

              function fractionAt(x) {
                return Math.min(1, Math.max(0, x / Math.max(1, width)))
              }

              // Remaining track, starting one gap past the active indicator and
              // stopping short of the dot. Pacman draws its own track as a row
              // of pellets, so this line and the stop dot both stand down.
              Rectangle {
                visible: !root.pacmanProgress
                x: Math.min(parent.width, wiggleBar.activeWidth + wiggleBar.gap)
                width: Math.max(0, parent.width - x - wiggleBar.stopSize - wiggleBar.gap)
                height: wiggleBar.barHeight
                radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              }

              // Active indicator -- Material 3 Expressive's wiggle. Drawn
              // on a Canvas because neither a Rectangle nor PanelSlider can
              // describe a sine. The wave travels by advancing its phase, and
              // the amplitude eases to zero when playback stops, so a paused
              // track shows a flat bar exactly as it does in Material.
              Canvas {
                id: wave
                anchors.fill: parent
                antialiasing: true

                property real phase: 0
                readonly property bool active: root.activePlayer !== null
                  && !!root.activePlayer.isPlaying
                property real amplitude: active ? Style.space(3) : 0
                readonly property real wavelength: Style.space(20)

                // Pac-Man geometry. He is drawn far larger than the 4dp bar the
                // other styles use, so the wedge reads as a mouth rather than a
                // notch -- the 18dp row this Canvas fills is what makes room.
                readonly property real pacRadius: Style.space(6)
                readonly property real pelletRadius: Style.space(1.5)
                readonly property real pelletPitch: Style.space(9)
                // Half-angle of the open mouth, in radians.
                readonly property real maxMouth: 0.62
                // How far ahead of his centre a pellet is swallowed. One value
                // for both the bite trigger and the pellet that disappears, so
                // the two can never drift apart.
                readonly property real eatOffset: pacRadius * 0.85

                // Chomping stops when playback does, easing over the same 260ms
                // the wiggle takes to flatten. It settles on a mouth that is
                // still open, not a shut one: a closed Pac-Man is a circle, and
                // a circle parked on a line is just a slider knob. Resting with
                // his mouth open keeps him legible while paused.
                property real chomp: active ? 1 : 0
                readonly property real restingMouth: 0.55

                // A bite is an event, not a rhythm. Counting the pellets he has
                // reached gives an integer that changes only on arrival, so the
                // mouth is driven by the dots rather than by a free-running
                // clock that happens to be chomping at thin air between them.
                readonly property int pelletsEaten: {
                  if (!root.pacmanProgress || width <= 0) return 0
                  var pitch = Math.max(2, pelletPitch)
                  var travel = Math.max(1, width - 2 * pacRadius)
                  var mouthX = pacRadius + wiggleBar.fraction * travel + eatOffset
                  return Math.max(0, Math.floor((mouthX - pacRadius) / pitch) + 1)
                }

                // 0 is wide open, 1 is shut. Snap closed, ease back open.
                property real bite: 0

                SequentialAnimation {
                  id: biteAnim
                  NumberAnimation {
                    target: wave; property: "bite"; to: 1
                    duration: 70; easing.type: Easing.InQuad
                  }
                  NumberAnimation {
                    target: wave; property: "bite"; to: 0
                    duration: 120; easing.type: Easing.OutQuad
                  }
                }

                onPelletsEatenChanged: {
                  if (root.popupOpen && root.pacmanProgress) biteAnim.restart()
                }

                Behavior on amplitude { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on chomp { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                NumberAnimation on phase {
                  // Always running, never stopped: `paused` may only be set on
                  // a running animation, and pausing rather than stopping is
                  // what keeps the wave's phase across a playback pause instead
                  // of snapping it back to zero. Repaints are gated on
                  // visibility below, so nothing is drawn when another progress
                  // style is selected.
                  //
                  // Pacman is deliberately NOT in this condition. Its bite is
                  // driven by arrivals, so it needs no per-frame clock at all,
                  // and leaving this running for it would repaint the canvas
                  // sixty times a second to move nothing.
                  running: true
                  paused: !root.popupOpen || !root.wiggleProgress || !wave.active
                  loops: Animation.Infinite
                  from: 0
                  to: 2 * Math.PI
                  duration: 1400
                  easing.type: Easing.Linear
                }

                onPhaseChanged: if (visible) requestPaint()
                onAmplitudeChanged: if (visible) requestPaint()
                onChompChanged: if (visible) requestPaint()
                onBiteChanged: if (visible) requestPaint()
                Connections {
                  target: root
                  function onProgressAnimationChanged() { wave.requestPaint() }
                }
                Component.onCompleted: requestPaint()

                Connections {
                  target: wiggleBar
                  function onActiveWidthChanged() { wave.requestPaint() }
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()

                  var mid = height / 2
                  var h = wiggleBar.barHeight
                  var r = h / 2

                  if (root.pacmanProgress) {
                    // Pac-Man eats his way along the track. The pellets ahead
                    // are the remaining time and the cleared line behind him is
                    // the elapsed time, so the maze reads as a progress bar
                    // without needing a second indicator on top of it.
                    var pacR = wave.pacRadius
                    var pitch = Math.max(2, wave.pelletPitch)

                    // He is inset by his own radius at both ends, or he would
                    // be sliced in half at 0% and again at 100%.
                    var travel = Math.max(1, width - 2 * pacR)
                    var pacX = pacR + wiggleBar.fraction * travel

                    // Cleared track behind him.
                    var trailEnd = pacX - pacR - Style.space(2)
                    if (trailEnd > r) {
                      ctx.lineWidth = h
                      ctx.lineCap = "round"
                      ctx.strokeStyle = Color.accent
                      ctx.beginPath()
                      ctx.moveTo(r, mid)
                      ctx.lineTo(trailEnd, mid)
                      ctx.stroke()
                    }

                    // Pellets still to eat. The grid is anchored to the left
                    // edge rather than to him, so they hold still while he
                    // advances through them instead of sliding along with him.
                    // The last slot is the power pellet, drawn larger.
                    var lastSlot = pacR
                    for (var gx = pacR; gx <= width - pacR; gx += pitch) lastSlot = gx

                    ctx.fillStyle = Style.selectedFillFor(root.bar.foreground, Color.accent)
                    for (var px = pacR; px <= width - pacR; px += pitch) {
                      // Eaten once he reaches it.
                      if (px < pacX + wave.eatOffset) continue
                      var pr = px === lastSlot
                        ? wave.pelletRadius * 1.7
                        : wave.pelletRadius
                      ctx.beginPath()
                      ctx.arc(px, mid, pr, 0, 2 * Math.PI)
                      ctx.fill()
                    }

                    // Pac-Man. The wedge is cut around angle 0 so the mouth
                    // faces the direction of travel; the pie is drawn from one
                    // lip clockwise round to the other.
                    // Wide open while travelling, snapped shut by the bite as
                    // he arrives at a pellet, and easing to a fixed open mouth
                    // when playback stops. Blended by `chomp` so stopping is a
                    // settle rather than a jump between two behaviours.
                    var openness = 1 - wave.bite
                    var mouth = wave.maxMouth
                      * (wave.chomp * openness + (1 - wave.chomp) * wave.restingMouth)
                    ctx.fillStyle = Color.accent
                    ctx.beginPath()
                    ctx.moveTo(pacX, mid)
                    ctx.arc(pacX, mid, pacR, mouth, 2 * Math.PI - mouth)
                    ctx.closePath()
                    ctx.fill()

                    // The eye, punched out in the surface colour so it stays a
                    // hole on any theme rather than a second painted dot.
                    ctx.fillStyle = Color.popups.background
                    ctx.beginPath()
                    ctx.arc(pacX - pacR * 0.12, mid - pacR * 0.42,
                            Math.max(1, pacR * 0.17), 0, 2 * Math.PI)
                    ctx.fill()
                    return
                  }

                  var end = wiggleBar.activeWidth
                  if (end <= 0) return

                  ctx.lineWidth = h
                  ctx.lineCap = "round"
                  ctx.lineJoin = "round"
                  ctx.strokeStyle = Color.accent
                  ctx.beginPath()

                  // Taper the last wavelength into the flat cap so the head of
                  // the wave meets the gap cleanly instead of being sliced
                  // mid-crest.
                  var taper = Math.max(1, wave.wavelength)
                  for (var x = 0; x <= end; x += 1) {
                    var fade = Math.min(1, (end - x) / taper)
                    var y = mid + wave.amplitude * fade
                      * Math.sin((x / wave.wavelength) * 2 * Math.PI + wave.phase)
                    if (x === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                  }
                  ctx.stroke()
                }
              }

              // Stop indicator: the dot Material parks at the end of the track.
              Rectangle {
                visible: !root.pacmanProgress
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: wiggleBar.stopSize
                height: wiggleBar.stopSize
                radius: width / 2
                color: Color.accent
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canSeek
                preventStealing: true
                onPressed: function(mouse) {
                  wiggleBar.dragFraction = wiggleBar.fractionAt(mouse.x)
                  wiggleBar.dragging = true
                }
                onPositionChanged: function(mouse) {
                  if (wiggleBar.dragging)
                    wiggleBar.dragFraction = wiggleBar.fractionAt(mouse.x)
                }
                onReleased: {
                  if (root.mediaService) root.mediaService.seekToFraction(wiggleBar.dragFraction)
                  wiggleBar.dragging = false
                }
                onCanceled: wiggleBar.dragging = false
              }
            }

            Row {
              id: timeRow
              anchors.top: parent.top
              anchors.topMargin: seekBlock.barArea
              anchors.left: parent.left
              anchors.right: parent.right

              Text {
                text: root.formatTime(
                  wiggleBar.dragging ? wiggleBar.dragFraction * root.trackLength
                  : seekSlider.dragging ? seekSlider.liveValue
                  : root.trackPosition)
                color: root.mutedText(0.32)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 2
                horizontalAlignment: Text.AlignLeft
              }

              Text {
                text: root.formatTime(root.trackLength)
                color: root.mutedText(0.32)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 2
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          // ------------------------------------------------------------ controls
          //
          // Symmetric around play/pause: shuffle | prev | -10s | play | +10s |
          // next | repeat. Shuffle and repeat flank the transport, and players
          // that do not advertise support for a control are dimmed and inert
          // rather than hidden, so the row does not reflow when you switch source.
          Row {
            id: controls
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(2)

            // One slot size for every button. Button derives its own size from
            // icon plus padding, so the larger play glyph and its wider padding
            // made that one button taller and the row read as ragged. Pinning
            // width and height makes the row uniform; Button centres its content
            // on both axes, so the bigger play icon still sits square in its slot.
            readonly property real slot: Style.space(30)

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: "󰒝"
              foreground: root.shuffleOn ? Color.accent : root.bar.foreground
              enabled: root.shuffleSupported
              opacity: !enabled ? 0.35 : (root.shuffleOn ? 1.0 : 0.6)
              tipText: (root.shuffleOn ? "Shuffle on" : "Shuffle off") + "  (x)"
              onClicked: if (root.mediaService) root.mediaService.toggleShuffle(false)
            }

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: "󰒮"
              foreground: root.bar.foreground
              enabled: root.activePlayer && root.activePlayer.canGoPrevious
              opacity: enabled ? 1.0 : 0.4
              tipText: "Previous  (p)"
              onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
            }

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: root.rewindGlyph
              foreground: root.bar.foreground
              enabled: root.canSeek
              opacity: enabled ? 1.0 : 0.4
              tipText: "Back " + root.seekStep + "s  (b)"
              onClicked: if (root.mediaService) root.mediaService.seekBy(-root.seekStep, false)
            }

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
              foreground: root.bar.foreground
              iconSize: Style.font.iconLarge
              enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
              opacity: enabled ? 1.0 : 0.4
              tipText: root.activePlayer && root.activePlayer.isPlaying ? "Pause  (space)" : "Play  (space)"
              onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
            }

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: root.forwardGlyph
              foreground: root.bar.foreground
              enabled: root.canSeek
              opacity: enabled ? 1.0 : 0.4
              tipText: "Forward " + root.seekStep + "s  (f)"
              onClicked: if (root.mediaService) root.mediaService.seekBy(root.seekStep, false)
            }

            TipButton {
              width: controls.slot; height: controls.slot
              iconText: "󰒭"
              foreground: root.bar.foreground
              enabled: root.activePlayer && root.activePlayer.canGoNext
              opacity: enabled ? 1.0 : 0.4
              tipText: "Next  (n)"
              onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
            }

            TipButton {
              width: controls.slot; height: controls.slot
              // repeat-off / repeat-all / repeat-one
              iconText: root.loopLabel === "Repeat track" ? "󰑘"
                : root.loopLabel === "Repeat all" ? "󰑖" : "󰑗"
              foreground: root.loopLabel === "Repeat off" ? root.bar.foreground : Color.accent
              enabled: root.loopSupported
              opacity: !enabled ? 0.35 : (root.loopLabel === "Repeat off" ? 0.6 : 1.0)
              tipText: root.loopLabel + "  (r)"
              onClicked: if (root.mediaService) root.mediaService.cycleLoop(false)
            }
          }

          // ------------------------------------------------------------ volume
          //
          // Only for players that implement MPRIS Volume. Browsers route their
          // audio through PipeWire and report volumeSupported false, so the row
          // is hidden for them rather than showing a slider that does nothing.
          Row {
            id: volumeRow
            visible: root.volumeSupported
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: volumeGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: root.volumeLevel <= 0 ? "󰖁"
                : root.volumeLevel < 0.5 ? "󰕿" : "󰕾"
              color: root.mutedText(0.26)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              width: Style.space(20)
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSlider {
              id: volumeSlider
              bar: root.bar
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - volumeGlyph.width - parent.spacing
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.volumeLevel
              // Applied while dragging as well as on release: a volume slider
              // that only lands when you let go is unusable for finding a
              // level by ear. Feedback is off -- the slider is the feedback.
              onMoved: function(value) {
                if (root.mediaService) root.mediaService.setVolume(value, false)
              }
              onReleased: function(value) {
                if (root.mediaService) root.mediaService.setVolume(value, false)
              }
            }
          }

          PanelSeparator {
            visible: root.sourcePlayers.length > 1
            foreground: root.bar.foreground
          }

          // Capped and scrollable. Six players running used to grow the popup
          // until it ran off the screen; now the list scrolls inside a fixed
          // ceiling and the rest of the popup keeps its place.
          Flickable {
            id: sourceScroll
            visible: root.sourcePlayers.length > 1
            width: parent.width
            height: Math.min(contentHeight, Style.space(132))
            contentWidth: width
            contentHeight: sourceList.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: sourceList
              width: sourceScroll.width
              spacing: Style.space(4)

              Repeater {
                model: root.sourcePlayers

                BorderSurface {
                  id: sourceRow
                  required property var modelData

                  readonly property var player: modelData
                  readonly property bool selected: root.activePlayer && player
                    && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
                  readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
                  readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

                  width: sourceList.width
                  height: sourceInner.implicitHeight + Style.space(10)
                  radius: Style.spacing.labelGap
                  color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
                  borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

                  // The app icon is anchored to the row's right edge and the text
                  // Row stops short of it, so a long title elides against the icon
                  // instead of sliding underneath it.
                  IconImage {
                    id: appIcon
                    anchors.right: parent.right
                    anchors.rightMargin: sourceRow.borderRight + Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Style.space(18)
                    source: root.appIconFor(sourceRow.player)
                    visible: source !== ""
                    opacity: sourceRow.selected ? 1.0 : 0.75
                  }

                  Row {
                    id: sourceInner
                    anchors.left: parent.left
                    anchors.right: appIcon.visible ? appIcon.left : parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
                    anchors.rightMargin: appIcon.visible ? Style.space(8) : sourceRow.borderRight + Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                      width: Style.space(18)
                      horizontalAlignment: Text.AlignHCenter
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      width: parent.width - Style.space(26)
                      spacing: Style.space(1)
                      anchors.verticalCenter: parent.verticalCenter

                      MetaText {
                        text: sourceRow.sourceTitle
                        font.pixelSize: Style.font.bodySmall
                        font.bold: sourceRow.selected
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      MetaText {
                        text: sourceRow.sourceDetail
                        color: root.mutedText(0.38)
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
                  }
                }
              }
            }
            }
        }

        // ------------------------------------------------------------ settings
        Column {
          id: settingsView
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "Position on bar (m)"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          ButtonGroup {
            options: [
              { value: "left", label: "Left" },
              { value: "center", label: "Center" },
              { value: "right", label: "Right" }
            ]
            value: root.barSection
            foreground: root.bar.foreground
            background: root.bar.background
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            // The bar widget panels drive their own cursor and never hand Tab
            // focus to a ButtonGroup; taking it here would trap Tab in the popup.
            focusable: false
            onChanged: function(section) { root.setBarSection(section) }
          }


          PanelSeparator { foreground: root.bar.foreground }

          Text {
            text: "Popup artwork (v)"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          ButtonGroup {
            options: [
              { value: "square", label: "Square" },
              { value: "vinyl", label: "Vinyl" }
            ]
            value: root.artworkStyle
            foreground: root.bar.foreground
            background: root.bar.background
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            focusable: false
            onChanged: function(style) { root.setArtworkStyle(style) }
          }


          PanelSeparator { foreground: root.bar.foreground }

          Text {
            text: "Progress animation (y)"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          ButtonGroup {
            options: [
              { value: "default", label: "Plain" },
              { value: "wiggle", label: "Wiggle" },
              { value: "pacman", label: "Pac-Man" }
            ]
            value: root.progressAnimation
            foreground: root.bar.foreground
            background: root.bar.background
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            // Three long labels overflow the narrowed popup at body size.
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(style) { root.setProgressAnimation(style) }
          }

        }

      }
    }
  }
}

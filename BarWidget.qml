import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Ui
import qs.Commons

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
  //   m      cycle section   s  settings      esc close
  //
  // Matched on event.text rather than Qt.Key_* so the letters follow the
  // active keyboard layout instead of hard-coding a QWERTY scancode.
  function handleKey(event) {
    if (!root.popupOpen) return
    var svc = root.mediaService
    var text = String(event.text || "").toLowerCase()
    var handled = true

    if (event.key === Qt.Key_Space) {
      if (svc) svc.runAction("playPause", false)
    } else if (event.key === Qt.Key_Escape) {
      root.close()
    } else if (text === "b") {
      if (svc) svc.seekBy(-10)
    } else if (text === "f") {
      if (svc) svc.seekBy(10)
    } else if (text === "n") {
      if (svc) svc.runAction("next", false)
    } else if (text === "p") {
      if (svc) svc.runAction("previous", false)
    } else if (text === "m") {
      var order = ["left", "center", "right"]
      var at = order.indexOf(root.barSection)
      root.setBarSection(order[(at < 0 ? 0 : at + 1) % order.length])
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
  readonly property string progressAnimation: String(setting("progressAnimation", "default"))
  readonly property bool wiggleProgress: progressAnimation === "wiggle"

  readonly property int progressDuration: wiggleProgress ? 300 : 140
  readonly property int progressEasing: wiggleProgress ? Easing.Bezier : Easing.OutCubic

  // Material's standard curve, cubic-bezier(0.4, 0, 0.2, 1). QML wants the
  // two control points plus the (1,1) endpoint.
  // Material's standard curve, cubic-bezier(0.4, 0, 0.2, 1) -- the wiggle is
  // Material 3 Expressive, so it keeps that motion.
  readonly property var progressBezier: wiggleProgress
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

  function setProgressAnimation(style) {
    if (["default", "wiggle"].indexOf(style) === -1) return
    if (style === root.progressAnimation) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.progressAnimation = style

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatTime(seconds) {
    return mediaService ? mediaService.formatTime(seconds) : "0:00"
  }

  property bool popupOpen: false
  property bool settingsOpen: false

  // Leaving the settings view open would mean the next summon lands on the
  // form rather than on what is playing, which is not what a media popup is
  // for. Reset whenever the popup closes, however it was closed.
  onPopupOpenChanged: if (!popupOpen) settingsOpen = false

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

  // Section changes go through `omarchy bar move`, but a per-widget setting is
  // an inline field on this widget's own layout entry, which the shell writes
  // through updateEntryInline -- the same path the clock uses when it cycles
  // its format. Applied to `settings` locally first so the artwork flips on
  // the click itself rather than after the config round-trip.
  function setArtworkStyle(style) {
    if (style !== "square" && style !== "vinyl") return
    if (style === root.artworkStyle) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.artworkStyle = style

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // `omarchy bar move` owns the shell.json write and the relayout; going
  // through it keeps this popup from hand-editing the layout and racing the
  // shell's own config watcher.
  // Consumed once, by the rebuilt widget, to put the popup back after a move.
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

    // The move rebuilds this widget, so hand the popup state to the service
    // before it goes.
    if (root.popupOpen && root.mediaService) {
      root.mediaService.restorePopup = true
      root.mediaService.restoreSettings = root.settingsOpen
    }
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

  // Shape contract for shell summon/hide/toggle routing: Bar.findPanelWidget
  // requires open(), close() and `opened` on the bar-widget root before it
  // will route to a widget at all. With these present,
  // `omarchy-shell shell toggle <plugin-id>` reaches this popup, and the bar
  // picks the instance on the focused monitor rather than opening one popup
  // per screen. Going through shell routing rather than a second IpcHandler
  // also avoids fighting the service for the single handler a target allows.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function toggle() { popupOpen = !popupOpen }
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
        sourceSize.width: Math.round(root.artSize * 2)
        sourceSize.height: Math.round(root.artSize * 2)
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

        Text {
          id: labelText
          text: root.title + (root.artist ? "  ·  " + root.artist : "")
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: labelText.text
          visible: scrollClip.needsScroll
          color: labelText.color
          font.family: labelText.font.family
          font.pixelSize: labelText.font.pixelSize
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
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " \u2014 " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // Keyboard focus for the popup hotkeys.
  //
  // PopupCard is a PopupWindow anchored to the bar, and Bar.qml declares its
  // layer surface as keyboardFocus: None -- so no key ever reaches the popup,
  // focus grab or not. That is not a guess: with a key handler inside the
  // popup, pressing keys produced zero events. The first-party panels avoid
  // this by being KeyboardPanel layer surfaces that take focus while open.
  // Rather than refactor this popup into one, this is a 1x1 overlay whose
  // only job is to hold keyboard focus while the popup is open. Its mask is
  // empty, so it is entirely click-through and cannot disturb the popup's
  // own click-outside dismissal.
  PanelWindow {
    id: keyWindow
    visible: root.popupOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "mediaplusplus-keys"
    WlrLayershell.layer: WlrLayer.Overlay
    // Prime with Exclusive, then settle on OnDemand -- the same two-phase
    // handoff KeyboardPanel performs, and for the same reason. Exclusive is
    // what actually wins focus for a freshly mapped surface, but while it is
    // held the compositor suppresses pointer hit-testing everywhere, which is
    // why holding it left the hotkeys working and every mouse click dead.
    // OnDemand keeps the focus already granted and gives the pointer back.
    property bool focusPrimed: false

    WlrLayershell.keyboardFocus: root.popupOpen
      ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    onVisibleChanged: {
      focusPrimed = false
      if (visible) focusPrimeTimer.restart()
      else focusPrimeTimer.stop()
    }

    // Re-run the prime. OnDemand keeps the pointer usable but does not hold
    // keyboard focus against focus-follows-mouse: crossing any window on the
    // way back to the popup hands focus to that window and the hotkeys go
    // quiet. Re-priming when the pointer lands on the popup takes focus back,
    // with the pointer-blocking Exclusive phase lasting only the 75ms below.
    function reclaimFocus() {
      if (!visible) return
      focusPrimed = false
      focusPrimeTimer.restart()
    }

    Timer {
      id: focusPrimeTimer
      // Long enough for the surface to map and take focus, short enough that
      // the pointer-blocking phase is imperceptible.
      interval: 75
      onTriggered: if (root.popupOpen) keyWindow.focusPrimed = true
    }
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    mask: Region {}

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) { root.handleKey(event) }
    }
  }

  // Taking keyboard focus clears PopupCard's own focus grab, and its grab
  // closes the popup when cleared -- so simply adding a focused surface made
  // the popup shut the instant it opened. The fix is to own the grab here
  // instead: PopupCard's is disabled (triggerMode "hover"), and this one
  // lists both surfaces, so focus moving between them is not "outside" and
  // click-outside dismissal still works.
  HyprlandFocusGrab {
    active: root.popupOpen
    // The bar belongs in here too. PopupCard's own grab listed the popup and
    // its anchor window; dropping the anchor meant the pointer crossing the
    // bar counted as "outside" and closed the popup out from under the click
    // that was on its way to it.
    windows: popup.anchorWindow
      ? [keyWindow, popup, popup.anchorWindow]
      : [keyWindow, popup]
    onCleared: root.close()
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    // Its grab is replaced by the one above, which also covers keyWindow.
    triggerMode: "hover"
    open: root.popupOpen

    // PopupCard's default property takes Items only, so the handler needs a
    // host. Non-blocking and on top: it observes the pointer entering the
    // popup without taking hover away from the buttons underneath.
    Item {
      anchors.fill: parent
      z: 100

      HoverHandler {
        blocking: false
        onHoveredChanged: if (hovered) keyWindow.reclaimFocus()
      }
    }
    contentWidth: popup.fittedContentWidth(Style.space(240))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

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

        Button {
          id: gearButton
          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.space(26)
          height: Style.space(26)
          iconText: root.settingsOpen ? "󰝚" : "󰒓"
          foreground: root.bar.foreground
          opacity: root.settingsOpen ? 1.0 : 0.55
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

          readonly property bool ready: artImage.status === Image.Ready
            && artImage.sourceSize.width > 0 && artImage.sourceSize.height > 0
          readonly property real aspect: ready
            ? artImage.sourceSize.width / artImage.sourceSize.height
            : (root.isVideo ? 16 / 9 : 1)
          readonly property real maxHeight: Style.space(134)

          visible: !root.vinylArtwork
          anchors.horizontalCenter: parent.horizontalCenter
          height: visible ? Math.min(maxHeight, column.width / Math.max(0.2, aspect)) : 0
          width: visible ? Math.min(column.width, height * Math.max(0.2, aspect)) : 0

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
            transform: [
              Rotation {
                origin.x: artTilt.width / 2
                origin.y: artTilt.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: -artFrame.hoverY * 13
              },
              Rotation {
                origin.x: artTilt.width / 2
                origin.y: artTilt.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: artFrame.hoverX * 13
              },
              Scale {
                origin.x: artTilt.width / 2
                origin.y: artTilt.height / 2
                xScale: artFrame.lifted ? 1.03 : 1.0
                yScale: artFrame.lifted ? 1.03 : 1.0
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

            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
              source: root.artUrl
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
              running: true
              paused: !(root.activePlayer && root.activePlayer.isPlaying)
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

              layer.enabled: true
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
                sourceSize.width: Math.round(vinylFrame.width * 2)
                sourceSize.height: Math.round(vinylFrame.height * 2)
                source: root.artUrl
                visible: status === Image.Ready && root.artUrl !== ""
              }
            }

            Item {
              id: discMask
              anchors.fill: parent
              visible: false
              layer.enabled: true

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

          Text {
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            text: root.artist
            color: root.mutedText(0.26)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
          }

          Text {
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: root.mutedText(0.43)
            font.family: root.bar.fontFamily
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
          readonly property real barArea: root.wiggleProgress
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
            visible: !root.wiggleProgress
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
            visible: root.wiggleProgress
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
            // stopping short of the dot.
            Rectangle {
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

              Behavior on amplitude { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

              NumberAnimation on phase {
                // Always running, never stopped: `paused` may only be set on
                // a running animation, and pausing rather than stopping is
                // what keeps the wave's phase across a playback pause instead
                // of snapping it back to zero. Repaints are gated on
                // visibility below, so nothing is drawn when another progress
                // style is selected.
                running: true
                paused: !wave.active
                loops: Animation.Infinite
                from: 0
                to: 2 * Math.PI
                duration: 1400
                easing.type: Easing.Linear
              }

              onPhaseChanged: if (visible) requestPaint()
              onAmplitudeChanged: if (visible) requestPaint()
              Component.onCompleted: requestPaint()

              Connections {
                target: wiggleBar
                function onActiveWidthChanged() { wave.requestPaint() }
              }

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                var end = wiggleBar.activeWidth
                if (end <= 0) return

                var mid = height / 2
                ctx.lineWidth = wiggleBar.barHeight
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

          Button {
            width: controls.slot; height: controls.slot
            iconText: "󰒝"
            foreground: root.shuffleOn ? Color.accent : root.bar.foreground
            enabled: root.shuffleSupported
            opacity: !enabled ? 0.35 : (root.shuffleOn ? 1.0 : 0.6)
            onClicked: if (root.mediaService) root.mediaService.toggleShuffle()
          }

          Button {
            width: controls.slot; height: controls.slot
            iconText: "󰒮"
            foreground: root.bar.foreground
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
          }

          Button {
            width: controls.slot; height: controls.slot
            iconText: "󰴪"
            foreground: root.bar.foreground
            enabled: root.canSeek
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.seekBy(-10)
          }

          Button {
            width: controls.slot; height: controls.slot
            iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            iconSize: Style.font.iconLarge
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
          }

          Button {
            width: controls.slot; height: controls.slot
            iconText: "󰵱"
            foreground: root.bar.foreground
            enabled: root.canSeek
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.seekBy(10)
          }

          Button {
            width: controls.slot; height: controls.slot
            iconText: "󰒭"
            foreground: root.bar.foreground
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
          }

          Button {
            width: controls.slot; height: controls.slot
            // repeat-off / repeat-all / repeat-one
            iconText: root.loopLabel === "Repeat track" ? "󰑘"
              : root.loopLabel === "Repeat all" ? "󰑖" : "󰑗"
            foreground: root.loopLabel === "Repeat off" ? root.bar.foreground : Color.accent
            enabled: root.loopSupported
            opacity: !enabled ? 0.35 : (root.loopLabel === "Repeat off" ? 0.6 : 1.0)
            onClicked: if (root.mediaService) root.mediaService.cycleLoop()
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          foreground: root.bar.foreground
        }

        Column {
          id: sourceList
          visible: root.sourcePlayers.length > 1
          width: parent.width
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

                  Text {
                    text: sourceRow.sourceTitle
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    text: sourceRow.sourceDetail
                    color: root.mutedText(0.38)
                    font.family: root.bar.fontFamily
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
          text: "Progress animation"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        ButtonGroup {
          options: [
            { value: "default", label: "Default" },
            { value: "wiggle", label: "Wiggle" }
          ]
          value: root.progressAnimation
          foreground: root.bar.foreground
          background: root.bar.background
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          focusable: false
          onChanged: function(style) { root.setProgressAnimation(style) }
        }

      }

    }
  }
}

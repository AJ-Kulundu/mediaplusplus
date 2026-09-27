import QtQuick
import QtQuick.Effects
import Quickshell
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
  function setBarSection(section) {
    if (!bar || !section || section === root.barSection) return
    bar.run("omarchy bar move " + bar.shellQuote(root.moduleName)
            + " --section " + bar.shellQuote(section))
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
        running: scrollClip.needsScroll && !root.popupOpen && !root.bar.vertical
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

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(300))
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
          readonly property real maxHeight: Style.space(168)

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
          height: visible ? Math.min(Style.space(168), column.width) : 0
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

            // Turns only while playing, and keeps its angle when paused so
            // resuming continues from where it stopped rather than snapping.
            RotationAnimation on rotation {
              running: root.activePlayer !== null && !!root.activePlayer.isPlaying
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 9000
            }

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: vinylFrame.discColor
              border.width: 1
              border.color: Style.normalFillFor(root.bar.foreground, Color.accent)
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
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }

              Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
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
          height: seekSlider.implicitHeight + timeRow.implicitHeight
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
            value: root.trackPosition
            enabled: root.canSeek
            opacity: root.canSeek ? 1.0 : 0.45
            onReleased: function(value) {
              if (root.mediaService) root.mediaService.seekToSeconds(value)
            }
          }

          Row {
            id: timeRow
            anchors.top: seekSlider.bottom
            anchors.left: parent.left
            anchors.right: parent.right

            Text {
              text: root.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.trackPosition)
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

              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
                anchors.rightMargin: sourceRow.borderRight + Style.space(8)
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
          text: "Position on bar"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        ButtonGroup {
          anchors.horizontalCenter: parent.horizontalCenter
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

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Moves the widget between bar sections. Dragging it on the bar does the same thing."
          color: root.mutedText(0.38)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        Text {
          text: "Popup artwork"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        ButtonGroup {
          anchors.horizontalCenter: parent.horizontalCenter
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

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Square shows the whole cover. Vinyl spins the cover as a record label while playing."
          color: root.mutedText(0.38)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

    }
  }
}

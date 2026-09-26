import QtQuick
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

  function close() { popupOpen = false }

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

        anchors.horizontalCenter: parent.horizontalCenter
        height: Math.min(maxHeight, column.width / Math.max(0.2, aspect))
        width: Math.min(column.width, height * Math.max(0.2, aspect))

        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

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
  }
}

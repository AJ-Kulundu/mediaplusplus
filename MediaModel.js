function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

// A track is identified by its title, artist or album -- never by artwork
// alone. Browsers leave a stale mpris:artUrl behind when a video is torn
// down, so a Stopped Brave still advertises cover art for a track it no
// longer has. Counting that as track metadata let an empty player outrank a
// paused one holding a real track, and the bar widget then went blank.
function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  return false
}

// Playing beats paused beats stopped. A paused player still holds a loaded
// track; a stopped one has thrown it away, so it should never be picked over
// a player that still has something to show. stoppedValue is
// MprisPlaybackState.Stopped, passed in by the caller.
function playbackRank(player, stoppedValue) {
  if (!player) return 0
  if (player.isPlaying) return 3
  if (stoppedValue !== undefined && player.playbackState === stoppedValue) return 1
  return 2
}

// Keep whichever of the two ranks higher, preferring the incumbent on a tie
// so iteration order still decides between two equally live players.
function preferByPlayback(current, candidate, stoppedValue) {
  if (!current) return candidate
  if (!candidate) return current
  return playbackRank(candidate, stoppedValue) > playbackRank(current, stoppedValue)
    ? candidate : current
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

var MIN_FUZZY_KEY = 4

function playerHasPlaybackStream(player, playbackStreams) {
  var playerKey = streamLabelKey(playerAppLabel(player))
  if (!playerKey) return false

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    var streamKey = streamLabelKey(rawStreamLabel(streams[i]))
    if (!streamKey) continue
    // Substring matching either way is what pairs "chrome" with "chromium",
    // but on a two- or three-letter key it pairs with almost anything, so
    // only an exact hit counts below the threshold.
    if (streamKey === playerKey) return true
    if (streamKey.length >= MIN_FUZZY_KEY && playerKey.indexOf(streamKey) !== -1) return true
    if (playerKey.length >= MIN_FUZZY_KEY && streamKey.indexOf(playerKey) !== -1) return true
  }

  return false
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""
  return [
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.trackArtUrl || ""
  ].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || ""
}

// Strip the characters that make Qt.mightBeRichText() true. For text handed
// to a Text item whose textFormat we cannot set -- the shared tooltip and the
// OSD are both upstream and both left on Text.AutoText. Removing "<" is what
// defeats tag detection; a lone "&" entity can still decode to a character,
// which is a cosmetic difference, not a security property.
function plainText(value) {
  return String(value || "").replace(/[<>]/g, "")
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = plainText(labelFor(player))
  if (label && player.trackArtist) return label + " \u2014 " + plainText(player.trackArtist)
  return label || fallback
}

// ---------------------------------------------------------------- media++
//
// Extensions over the stock omarchy.media model: raw metadata access, an
// audio/video classification used to pick the art placeholder, and a
// duration formatter for the seek bar.

var VIDEO_EXTENSIONS = /\.(mp4|mkv|webm|avi|mov|m4v|flv|wmv|mpg|mpeg|ogv|ts)(\?|#|$)/i
var VIDEO_HOSTS = /(youtube\.com|youtu\.be|vimeo\.com|twitch\.tv|dailymotion\.com|netflix\.com|primevideo\.com|disneyplus\.com|crunchyroll\.com|peertube)/i
var VIDEO_APPS = /(mpv|vlc|celluloid|totem|haruna|smplayer|kodi|clapper|dragon|freetube)/i
var AUDIO_APPS = /(spotify|rhythmbox|clementine|strawberry|audacious|amberol|elisa|lollypop|cmus|mpd|ncspot|tauon|quodlibet|deadbeef|sayonara)/i
var BROWSER_APPS = /(brave|chromium|google-chrome|chrome|firefox|librewolf|zen|vivaldi|edge|epiphany|qutebrowser)/i

// MPRIS metadata values arrive as either scalars or single-element arrays
// (xesam:artist is always a list). Normalise both to a plain string.
function metadataValue(player, key) {
  var md = player && player.metadata ? player.metadata : null
  if (!md) return ""
  var value = md[key]
  if (value === undefined || value === null) return ""
  if (Array.isArray(value)) return String(value.length ? value[0] : "")
  return String(value)
}

// Best-effort audio/video classification. Only used to choose the fallback
// placeholder glyph and the tooltip wording -- the art frame itself is shaped
// by the artwork's real aspect ratio, which is more reliable than any guess.
// Returns "video", "audio", or "unknown".
function mediaKind(player) {
  if (!player) return "unknown"

  var app = String(playerAppLabel(player) || "").toLowerCase()
  if (VIDEO_APPS.test(app)) return "video"
  if (AUDIO_APPS.test(app)) return "audio"

  var url = metadataValue(player, "xesam:url")
  if (url && (VIDEO_EXTENSIONS.test(url) || VIDEO_HOSTS.test(url))) return "video"

  // An album tag is a strong audio signal; browsers playing video never set it.
  if (player.trackAlbum) return "audio"

  // Browsers expose no xesam:url and no album for video (verified against
  // Brave, which reports only title/artist/artUrl). An album-less browser
  // session is far more often video than audio, and this only picks the
  // placeholder glyph -- the art frame is shaped by the real image.
  if (BROWSER_APPS.test(app)) return "video"

  return "unknown"
}

// Seconds -> "m:ss", or "h:mm:ss" once past an hour.
function formatTime(seconds) {
  var total = Number(seconds)
  if (!isFinite(total) || total < 0) total = 0
  total = Math.floor(total)

  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }

  return hours > 0
    ? hours + ":" + pad(minutes) + ":" + pad(secs)
    : minutes + ":" + pad(secs)
}

// None -> Playlist -> Track -> None. Takes and returns MprisLoopState values,
// passed in by the caller so this file stays free of QML imports.
function nextLoopState(current, noneValue, trackValue, playlistValue) {
  if (current === noneValue) return playlistValue
  if (current === playlistValue) return trackValue
  return noneValue
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    canHandleAction: canHandleAction,
    canCycleSource: canCycleSource,
    playbackRank: playbackRank,
    preferByPlayback: preferByPlayback,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    osdMessage: osdMessage,
    plainText: plainText,
    metadataValue: metadataValue,
    mediaKind: mediaKind,
    formatTime: formatTime,
    nextLoopState: nextLoopState
  }
}

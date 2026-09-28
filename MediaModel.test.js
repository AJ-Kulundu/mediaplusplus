// Unit tests for MediaModel.js -- the pure logic behind player selection,
// stream matching and formatting. Run with: node MediaModel.test.js
//
// MediaModel.js is deliberately free of QML imports (enum values are passed
// in by the caller) precisely so it can be exercised here, outside a running
// shell. Everything below is a plain object standing in for an MprisPlayer.

var m = require("./MediaModel.js")

var passed = 0, failed = 0
function eq(actual, expected, label) {
  var ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (ok) { passed++; return }
  failed++
  console.error("  FAIL " + label + "\n    expected " + JSON.stringify(expected)
                + "\n    actual   " + JSON.stringify(actual))
}

// MprisPlaybackState.Stopped, as the shell passes it in.
var STOPPED = 0

// -- hasTrackMetadata ------------------------------------------------------
// The regression that made the bar widget vanish: a browser leaves a stale
// mpris:artUrl behind after a video is torn down, with no title or artist.
eq(m.hasTrackMetadata({ trackArtUrl: "file:///tmp/stale" }), false, "artUrl alone is not a track")
eq(m.hasTrackMetadata({ trackTitle: "Doha" }), true, "title is a track")
eq(m.hasTrackMetadata({ trackArtist: "Seyi Vibez" }), true, "artist is a track")
eq(m.hasTrackMetadata({ trackAlbum: "Loading" }), true, "album is a track")
eq(m.hasTrackMetadata(null), false, "no player is not a track")

// -- playbackRank / preferByPlayback --------------------------------------
var playing = { isPlaying: true }
var paused  = { isPlaying: false, playbackState: 2 }
var stopped = { isPlaying: false, playbackState: STOPPED }
eq(m.playbackRank(playing, STOPPED), 3, "playing ranks highest")
eq(m.playbackRank(paused, STOPPED), 2, "paused outranks stopped")
eq(m.playbackRank(stopped, STOPPED), 1, "stopped ranks lowest")
eq(m.playbackRank(null, STOPPED), 0, "absent ranks below everything")
eq(m.preferByPlayback(stopped, paused, STOPPED), paused, "paused beats stopped")
eq(m.preferByPlayback(paused, stopped, STOPPED), paused, "order does not matter")
eq(m.preferByPlayback(null, stopped, STOPPED), stopped, "anything beats nothing")
eq(m.preferByPlayback(paused, playing, STOPPED), playing, "playing beats paused")
// Ties keep the incumbent, so iteration order still decides between equals.
var a = { isPlaying: true, id: "a" }, b = { isPlaying: true, id: "b" }
eq(m.preferByPlayback(a, b, STOPPED), a, "a tie keeps the incumbent")

// -- stream matching -------------------------------------------------------
function stream(name) { return { isStream: true, ready: true, properties: { "application.name": name } } }
// The substring test is what pairs a player against a differently-spelled
// stream name. Note "chromium" does NOT contain "chrome" -- the pairing that
// actually occurs is against the longer, prefixed form.
eq(m.playerHasPlaybackStream({ identity: "Google Chrome" }, [stream("chrome")]), true,
   "chrome matches google-chrome")
eq(m.playerHasPlaybackStream({ identity: "Chromium" }, [stream("chromium")]), true,
   "chromium matches itself")
eq(m.playerHasPlaybackStream({ identity: "Chromium" }, [stream("chrome")]), false,
   "chromium does not contain chrome")
eq(m.playerHasPlaybackStream({ identity: "Spotify" }, [stream("spotify")]), true,
   "exact match")
eq(m.playerHasPlaybackStream({ identity: "Spotify" }, [stream("Firefox")]), false,
   "unrelated names do not match")
// Short keys used to match almost anything through the substring test.
eq(m.playerHasPlaybackStream({ identity: "mpd" }, [stream("mpdris-proxy")]), false,
   "a 3-letter key does not fuzzy-match")
eq(m.playerHasPlaybackStream({ identity: "mpd" }, [stream("mpd")]), true,
   "a short key still matches exactly")
eq(m.playerHasPlaybackStream(null, []), false, "no player has no stream")

// -- formatTime ------------------------------------------------------------
eq(m.formatTime(0), "0:00", "zero")
eq(m.formatTime(61), "1:01", "pads seconds")
eq(m.formatTime(599), "9:59", "under ten minutes")
eq(m.formatTime(3600), "1:00:00", "rolls into hours")
eq(m.formatTime(3661), "1:01:01", "pads within hours")
eq(m.formatTime(-5), "0:00", "negative clamps to zero")
eq(m.formatTime(NaN), "0:00", "NaN clamps to zero")
eq(m.formatTime(undefined), "0:00", "undefined clamps to zero")

// -- nextLoopState ---------------------------------------------------------
// None -> Playlist -> Track -> None, with the enum values passed in.
var NONE = 0, TRACK = 1, PLAYLIST = 2
eq(m.nextLoopState(NONE, NONE, TRACK, PLAYLIST), PLAYLIST, "none -> playlist")
eq(m.nextLoopState(PLAYLIST, NONE, TRACK, PLAYLIST), TRACK, "playlist -> track")
eq(m.nextLoopState(TRACK, NONE, TRACK, PLAYLIST), NONE, "track -> none")

// -- plainText / osdMessage ------------------------------------------------
// The tooltip and the OSD are upstream Text items left on AutoText, so the
// angle brackets that make Qt.mightBeRichText() true have to go.
eq(m.plainText("<b>hi</b>"), "bhi/b", "strips angle brackets")
eq(m.plainText(null), "", "null is empty")
eq(m.osdMessage({ trackTitle: "Baby", trackArtist: "Joeboy" }, "x"), "Baby — Joeboy",
   "title and artist join with an em dash")
eq(m.osdMessage({ trackTitle: "Baby" }, "x"), "Baby", "title alone")
eq(m.osdMessage(null, "Play/pause"), "Play/pause", "falls back with no player")

// -- mediaKind -------------------------------------------------------------
eq(m.mediaKind({ identity: "Spotify", trackAlbum: "Loading" }), "audio", "spotify is audio")
eq(m.mediaKind({ identity: "mpv" }), "video", "mpv is video")
eq(m.mediaKind({ identity: "Brave" }), "video", "album-less browser is video")
eq(m.mediaKind({ identity: "Brave", trackAlbum: "Loading" }), "audio", "an album makes it audio")
eq(m.mediaKind(null), "unknown", "no player is unknown")

// -- isProxyPlayer ---------------------------------------------------------
eq(m.isProxyPlayer({ dbusName: "org.mpris.MediaPlayer2.playerctld" }), true, "playerctld is a proxy")
eq(m.isProxyPlayer({ dbusName: "org.mpris.MediaPlayer2.spotify" }), false, "spotify is not")

console.log((failed ? "FAILED" : "ok") + " -- " + passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)

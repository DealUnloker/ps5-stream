# ps5-stream

Receive your PS5's built-in broadcast on a Mac and watch it in a low-latency player window. No capture card and no Remote Play, so the controller stays paired to the console and you keep playing on the TV.

The PS5 starts its normal built-in Twitch broadcast. Your Mac answers the console's DNS lookups for Twitch's ingest servers with its own address, so the 1080p60 stream lands on the Mac instead of Twitch and opens in a player window.

```
PS5 ── "where is Twitch ingest?" ──▶ dnsmasq on the Mac ──▶ "right here"
PS5 ── RTMP :1935 ──▶ MediaMTX on the Mac ──▶ mpv window "PS5"
```

Nothing is installed on the console and nothing reaches Twitch: your channel stays offline.

What you do with the window is up to you: watch it on a second screen, or share it in a call, for example in Discord (see [Sharing the window](#sharing-the-window)).

## Contents

- [What you need](#what-you-need)
- [Install](#install)
- [Setup](#setup)
- [Usage](#usage)
- [Sharing the window](#sharing-the-window)
- [Latency](#latency)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Security notes](#security-notes)
- [How it works](#how-it-works)
- [Credits](#credits)

## What you need

- A Mac with [Homebrew](https://brew.sh). Tested on Apple Silicon.
- A PS5 on the same local network as the Mac.
- A Twitch account linked on the PS5. It is only used to press "Go Live"; nothing is sent to it.

## Install

```bash
git clone https://github.com/DealUnloker/ps5-stream.git
cd ps5-stream
brew bundle
```

`brew bundle` installs `dnsmasq`, `mediamtx` and `mpv`. Nothing runs as root and nothing is installed as a background service.

## Setup

1. **Link Twitch** (once). On the PS5: Settings → Users and Accounts → Link with Other Services → Twitch.

2. **Point the PS5's DNS at the Mac.** Run `./start.sh` on the Mac: it prints the Mac's address. On the PS5: Settings → Network → Settings → Set Up Internet Connection → select your network → Advanced Settings → DNS Settings → Manual.
   - Primary DNS: the Mac's address.
   - Secondary DNS: the Mac's address again, or leave it at `0.0.0.0`.

3. **Restart the PS5** the first time, so it forgets addresses it resolved earlier.

The secondary DNS never points at a real resolver on purpose. With one there, the console can fall back to it and the broadcast goes live on real Twitch. With the Mac as the only DNS server, the stream either lands on the Mac or does not start.

The price is that the console has no internet unless `start.sh` is running. When you are done, switch DNS Settings back to Automatic, and to Manual again for the next session.

The Mac's address can change when it reconnects to the network. If the PS5 reports no internet while `start.sh` is running, compare the address `start.sh` prints with the Primary DNS on the PS5. Reserving the address for the Mac in your router (DHCP reservation) avoids this, but is optional.

## Usage

1. On the Mac:

   ```bash
   ./start.sh
   ```

   Wait for `Ready`.

2. On the PS5: press the Create button → Broadcast → Twitch → Go Live.

3. A window titled **PS5** opens on the Mac by itself.

4. When you are done: stop the broadcast on the PS5, then press Ctrl+C in the terminal. Switch the PS5's DNS Settings back to Automatic, or the console stays offline.

The player is locked on purpose so a stray key cannot break the stream: pause, seeking and media keys are disabled. Only these work: `f` or a double click (fullscreen), `Esc` (leave fullscreen), `↑` / `↓` (volume) and `m` (mute). If you close the window or the player crashes, it reopens within a few seconds.

Broadcast resolution and voice chat audio are PS5 settings: Settings → Captures and Broadcasts → Broadcasts.

## Sharing the window

The **PS5** window is an ordinary macOS window, so any app that can share a window can show it to other people.

In Discord: join a voice channel or a call → Share Your Screen → pick the **PS5** window and enable audio sharing.

## Latency

The player holds video back so that it matches the sound, so the audio output device on the Mac decides how far the window lags behind the TV.

Measured on a live PS5 stream, as the gap between the newest data received and the frame being shown:

| Mac audio output | `--audio-buffer` | Player delay |
| --- | --- | --- |
| Bluetooth headset | 0.3 | ~470 ms |
| USB headset | 0.3 | ~295 ms |
| USB headset | 0.05 (default here) | ~45 ms |
| USB headset | 0 | ~30 ms, audio dropouts |
| No audio | n/a | 0 ms |

So: use a wired or USB audio device on the Mac. Bluetooth adds about half a second that no setting removes.

These numbers cover the Mac side only. The PS5's own encoding delay, drawing the window (1–3 frames) and, if you share the window, the delay of the app you share it through come on top.

The player also returns to the live edge by itself. When playback stalls (a display reconnects, the network hiccups), the stream keeps arriving, and a plain player would stay that far behind until the end of the broadcast. Here it plays the backlog at up to 2× speed until it is gone: a 5-second stall is caught up in about 5 seconds.

## Configuration

Environment variables for `start.sh`:

| Variable | Purpose |
| --- | --- |
| `PS5_STREAM_IP` | The Mac's LAN address, if auto-detection picks the wrong interface |
| `PS5_STREAM_DEBUG=1` | Print the console's DNS queries and MediaMTX connections. The output contains your Twitch stream key: do not show this terminal on stream |

Files:

| File | What to change there |
| --- | --- |
| [start.sh](start.sh) | `INGEST_DOMAINS`: the Twitch ingest domains answered with the Mac's address |
| [mediamtx.yml](mediamtx.yml) | The player command line, including `--audio-buffer` |
| [mpv-input.conf](mpv-input.conf) | The only key bindings active in the player window |
| [mpv-catchup.lua](mpv-catchup.lua) | When and how fast the player catches up after a stall |

Stop the broadcast before editing `mediamtx.yml`: MediaMTX reloads the file when it changes, which can drop a running stream.

## Troubleshooting

- **The PS5 says there is no internet.** `start.sh` is not running, or the Mac's address changed: compare the address `start.sh` prints with the Primary DNS on the PS5, then repeat the connection test. If you are not streaming, switch DNS Settings to Automatic.

- **`Address already in use` on start.** A previous `start.sh` is still running in another terminal tab: stop it with Ctrl+C. If it is not that, another program holds port 53 or 1935 (often a VPN client with its own DNS): `sudo lsof -nP -i :53 -i :1935`.

- **No window opens and your Twitch channel is live.** The DNS override did not work. Run `PS5_STREAM_DEBUG=1 ./start.sh`, start the broadcast and look at which Twitch host the console asks for. If its domain is not in `INGEST_DOMAINS`, add it. If the console sends no queries at all, it is not using this DNS server: check the PS5 network settings (Secondary DNS must be the Mac's address or `0.0.0.0`) and restart the console. A router that hands out a DNS server over IPv6 can cause the same symptom.

- **No window opens, Twitch is offline, and the PS5 reports a broadcast error.** The console reached the Mac but not with plain RTMP on port 1935. Run with `PS5_STREAM_DEBUG=1` and check whether MediaMTX logs a connection.

- **The window lags noticeably behind the TV.** See [Latency](#latency): switch the Mac's audio output away from Bluetooth. A delay that appears after a stall goes away by itself within a few seconds.

- **Audio crackles or drops out.** Raise `--audio-buffer` in `mediamtx.yml` to `0.1`. The video delay grows by the same amount.

- **Viewers of a shared window hear nothing.** Enable audio sharing when you pick the window, and give the sharing app (Discord, for example) the Screen Recording permission in System Settings → Privacy & Security.

- **macOS asks about incoming connections.** Allow them for `dnsmasq` and `mediamtx`.

## Limitations

- Twitch broadcasts only. The PS5's YouTube broadcast is reported to stop after about a minute when the stream never reaches YouTube.
- 1080p60 at about 6 Mbit/s is the ceiling of the PS5's built-in broadcast. A screen share can lower it further: Discord without Nitro shows 720p30.
- You get exactly what the PS5 would send to Twitch. Scenes where a game blocks broadcasting are replaced by the console's placeholder, and voice chat is included only if you enable it in the PS5 broadcast settings.
- While the PS5's DNS points at the Mac, the console cannot broadcast to real Twitch, and it is offline whenever `start.sh` is not running. Switch DNS Settings back to Automatic for either.
- macOS only.
- This relies on undocumented behaviour of the PS5 and Twitch. A system update on either side can break it.

## Security notes

- While `start.sh` runs, the Mac is a DNS server and an RTMP server for everyone on your local network. Use it on a network you trust.
- The stream path contains your Twitch stream key. The defaults keep it out of sight: the log level is `warn` and the player window has a fixed title. `PS5_STREAM_DEBUG=1` prints it.
- If the key does leak, reset it in the Twitch dashboard under Settings → Stream.

## How it works

Real Twitch ingest uses RTMPS, and the PS5 validates the certificate, so that connection cannot be redirected. What makes this work is that the console resolves hosts under `contribute.live-video.net` and publishes to them with plain RTMP on port 1935.

`start.sh` runs two programs in the foreground and stops both on Ctrl+C:

- **dnsmasq** forwards every query to `1.1.1.1` and `8.8.8.8`, except the ingest domains, which it answers with the Mac's address.
  - `ingest.twitch.tv` is left alone. It is the HTTPS endpoint that tells the console which ingest server to use, and it must stay real.
  - IPv6 (AAAA) queries for the ingest domains get an empty answer. Otherwise the console would receive Twitch's real IPv6 addresses.
  - The cache is off. With it on, a real address cached from another name's CNAME chain was served in spite of the override.
  - It listens on `0.0.0.0`, because macOS lets a non-root process bind port 53 on all addresses but not on a specific one.
- **MediaMTX** accepts RTMP on port 1935 with every other protocol disabled. When a stream appears it launches `mpv` on it and relaunches the player if it exits.

Stream as sent by the PS5: H.264 Main, 1920×1080 at 59.94 fps, about 6 Mbit/s, a keyframe every 2 seconds, no B-frames, AAC stereo at 48 kHz.

Tested in November 2026 with dnsmasq 2.93, MediaMTX 1.21.4 and mpv 0.42.

## Credits

The idea of redirecting the PS5's Twitch ingest lookup comes from Yash Garg's write-up, [Hijacking the PS5's RTMP stream](https://yashgarg.dev/posts/hijacking-ps5-rtmp-stream/).

## License

[MIT](LICENSE).

This project is not affiliated with or endorsed by Sony Interactive Entertainment, Twitch or Discord. PlayStation and PS5 are trademarks of Sony Interactive Entertainment Inc.

# IMFPlayer

A simple, modern **IMF (id Music Format) player written in Swift** for macOS.

This project is a clean Swift reimplementation of the classic `id_sd`-style IMF playback pipeline, using **AVAudioEngine** for audio output and the well-tested **DOSBox dbopl** core for OPL2 synthesis. It intentionally avoids SDL and timer-based loops in favor of a sample-accurate, pull-based audio design.

The result is accurate, stable playback of IMF music on modern macOS systems.

Credit to the original source materials for this project:
http://sourceforge.net/projects/clonekeenplus/files/Tools/IMFPlayer/

---

## Features

- Swift IMF parser and sequencer (Type 0 and Type 1)
- Sample-accurate timing (no polling loops or timers)
- OPL2 synthesis via DOSBox `dbopl`
- AVAudioEngine streaming output (Float32)
- Command-line interface
- No SDL2 or platform-specific audio hacks

---

## Architecture Overview

Classic DOS IMF playback (`id_sd`) combined sequencing, timing, and hardware access in one module.  
This project **preserves the behavior** while modernizing the structure:

- **IMFParser**  
  Parses IMF files into register write events and delays.

- **IMFSequencer**  
  Advances IMF ticks deterministically in sample time.

- **OPLDriver**  
  Swift-facing wrapper around the DOSBox `dbopl` core.

- **AudioEngine**  
  Uses `AVAudioEngine` + `AVAudioSourceNode` to pull audio frames.

All sequencing happens inside the audio callback, ensuring stable timing and glitch-free playback.

---

## Building & Running

### Requirements

- macOS
- Xcode or Swift toolchain
- Swift 5.9+

### Build & Run

```bash
swift run -c release -- IMFPlayerSwift path/to/music.imf
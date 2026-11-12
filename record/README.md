[![Release](https://img.shields.io/pub/v/record.svg)](https://pub.dev/packages/record)
[![dl](https://img.shields.io/pub/dm/record?color=fe8e86)]()
[![Using melos](https://img.shields.io/badge/maintained%20with-melos-linen.svg)](https://github.com/invertase/melos)


Audio recorder from microphone to a given file path or stream.  

No external dependencies:

- On Android, AudioRecord and MediaCodec or MediaRecorder.
- On iOS and macOS, AVFoundation.
- On Windows, MediaFoundation.
- On web, well... your browser! (and its underlying platform).

External dependencies:
- On linux, encoding is provided by `parecord`, `pactl` and `ffmpeg`. It **must** be installed separately.

## Platform feature parity matrix
| Feature          | Android       | iOS             | web     | Windows    | macOS  | linux
|------------------|---------------|-----------------|---------|------------|-------|-----------
| pause/resume     | ✔️            |   ✔️             | ✔️     |      ✔️    | ✔️    |  ✔️
| amplitude(dBFS)  | ✔️            |   ✔️             |  ✔️     |    ✔️     |  ✔️   |  ✔️
| permission check | ✔️            |   ✔️             |  ✔️    |            |  ✔️   |
| num of channels  | ✔️            |   ✔️             |  ✔️    |    ✔️      |  ✔️   |  ✔️
| device selection | ✔️ 1 / 2      | (auto BT/mic)    |  ✔️    |    ✔️      |  ✔️   |  ✔️
| auto gain        | ✔️ 2          | ✔️ 3             | ✔️      |            |  ✔️ 3     | 
| echo cancel      | ✔️ 2          | ✔️ 3             | ✔️      |            |  ✔️ 3     | 
| noise suppresion | ✔️ 2          |                  | ✔️      |            |       | 

## File
| Encoder         | Android        | iOS     | web     | Windows | macOS   | linux
|-----------------|----------------|---------|---------|---------|---------|---------
| aacLc           | ✔️            |   ✔️    |  ?      |   ✔️    |  ✔️    |  ✔️ 
| aacEld          | ✔️            |   ✔️    |   ?     |         |  ✔️    | 
| aacHe           | ✔️            |         |   ?     |         |         |   
| amrNb           | ✔️            |   ✔️     |  ?      |   ✔️    |         |  
| amrWb           | ✔️            |         |  ?      |          |        |  
| opus            | ✔️            |   ✔️ 4    |  ?       |         |         |  ✔️ 
| wav             | ✔️ 2          |   ✔️    |   ✔️   |    ✔️    |   ✔️  |   ✔️ 
| flac            | ✔️ 2          |    ✔️    |  ?     |  ✔️     |   ✔️   |   ✔️
| pcm16bits       | ✔️ 2          |   ✔️    |  ✔️    |   ✔️    |  ✔️    |  ✔️

?: from my testings:
| Encoder         | Firefox    | Chrome based   | Safari
|-----------------|------------|----------------|---------
| aacLc           |            |                |  ✔️*
| opus            | ✔️*        |   ✔️*           | 
| wav             | ✔️        |   ✔️           |   ✔️
| pcm16bits       | ✔️        |   ✔️           |  ✔️

\* Sample rate output is determined by your settings in OS. Bit depth is likely 32 bits.

wav and pcm16bits are provided by the package directly.

## Stream
| Encoder       | Android | iOS | web | Windows | macOS | linux |
|---------------|---------|-----|-----|---------|-------|-------|
| aacLc       * | ✔️ 2   | ✔️  |     | ✔️     | ✔️    |       |
| pcm16bits     | ✔️ 2   | ✔️  | ✔️  | ✔️     | ✔️   | ✔️    |

\* AAC is streamed with raw AAC with ADTS headers, so it's directly readable through a file!  
1. Bluetooth telephony device link (SCO) is automatically done but there's no phone call management.
2. Unsupported on legacy Android recorder.
3. Stream mode only.
4. Opus in CAF container. This means that your file will be playable only on iOS platforms.

## Usage

```dart
import 'package:record/record.dart';

final record = AudioRecorder();

// Check and request permission if needed
if (await record.hasPermission()) {
  // Start recording to file
  await record.start(const RecordConfig(), path: 'aFullPath/myFile.m4a');
  // ... or to stream
  final stream = await record.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits));
}

// Stop recording...
final path = await record.stop();
// ... or cancel it (and implicitly remove file/blob).
await record.cancel();

record.dispose(); // As always, don't forget this one.
```

## Setup, permissions and others

Background recording: See [docs](https://github.com/llfbandit/record/blob/main/doc/bg_recording.md).

### Android
[Setup](https://github.com/llfbandit/record/blob/main/record_android/README.md).

- min SDK: 23 (amrNb/amrWb: 26, Opus: 29)

### iOS
Add this to the ios/Runner/Info.plist file:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Some message to describe why you need this permission</string>
```
- min SDK: 12.0

### macOS
Add this to the macos/Runner/Info.plist file:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Some message to describe why you need this permission</string>
```

- In capabilities, activate "Audio input" in debug AND release schemes.  
- or directly in *.entitlements files
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

- min SDK: 10.15

### Linux

`parecord`, `pactl` and `ffmpeg` dependencies are required and widely available on your system.

- `parecord`: Used for audio input.
- `pactl`: Used for utility methods like getting available devices.
- `ffmpeg`: Used for encoding and output.

On Ubuntu 24.04.3 LTS, you can install them using:
```bash
sudo apt install pulseaudio-utils ffmpeg

## HarmonyOS private distribution

The private `record 7.1.2` includes its native HarmonyOS implementation in `ohos/`.
The manifest registers `RecordOhosPlugin` directly. Applications depend only on
`record`; there is no separate HarmonyOS Pub package to publish or resolve.
Android, iOS, desktop and web retain the official platform dependencies and Dart API.

Official source: https://github.com/llfbandit/record.git, record 7.1.2 release commit
`075cd07e70855d1c9d769c9c61add37e5ef78de2` (no 7.1.2 tag), with matching production
Dart sources. Local branch: `adapt/record-7.1.2-ohos`. Git `origin` is the fork at
`https://github.com/wangweicheng7/record.git`; `upstream` retains the official
repository. The CPF reference checkout is retained in
`upstream/fluttertpc_record` under the package workspace.

## Supported recording

- WAV PCM16 and raw PCM16 files, with exact header finalization before `stop()` completes.
- PCM16 streams through the standard record event channel.
- 8, 16, 32, 44.1 and 48 kHz; mono and stereo, subject to device support. A device format mismatch is reported as an error.
- Microphone permission checks/requests, recording state, dBFS peak amplitude, pause/resume, cancellation with file removal, and disposal.

AAC, AMR, Opus, FLAC and other encoded formats are explicitly unsupported. `isEncoderSupported()` returns true only for WAV and PCM16; streaming requires PCM16. Select an explicit supported encoder instead of the default AAC encoder.

Manual auto gain, echo cancellation and noise suppression switches, explicit device selection and background recording are not provided. Set the three processing switches to false. Capture uses the system microphone source; system audio processing is device-dependent. `listInputDevices()` returns an empty list, as on record's mobile implementations. Stop or cancel recording when the application leaves the foreground.

The host application declares and explains `ohos.permission.MICROPHONE` in its module manifest. `hasPermission(request: false)` never opens a permission dialog. Starting without permission returns an error.

```dart
final recorder = AudioRecorder();
if (await recorder.hasPermission()) {
  await recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 48000,
      numChannels: 1,
    ),
    path: '/application/sandbox/voice.wav',
  );
  final path = await recorder.stop();
}
await recorder.dispose();
```

## Sources and compatibility

- Official repository: https://github.com/llfbandit/record.git
- Main package baseline: `record 7.1.2`, commit `075cd07e70855d1c9d769c9c61add37e5ef78de2`. The official repository has no `7.1.2` tag; this commit contains the matching pubspec and production Dart sources, verified against the installed release.
- Platform contract: hosted `record_platform_interface ^2.1.0`; native method/state/PCM event channels follow that contract. No duplicate Dart AudioRecorder API is introduced.
- Reference implementation: https://gitcode.com/CPF-Flutter/fluttertpc_record.git, tag `6.1.2-ohos-1.0.0`, commit `19dd2a305eb0ecd122a9f700c0ed43186da78195`, package `record_ohos/`.
- The original pub.dev `record_ohos 1.0.0` archive was downloaded and SHA256 verified (`549fc35c418e46ff4bdc6eabcf1ad27295591c93470123e5cf8b58ce669d03f7`). A minimal dependency resolution with public `record 7.1.2` failed because the required interface versions are incompatible. The published native file/stream entry points and codec selection were inspected directly.
- The public record_ohos 1.0.0 uses platform interface 1.x. The CPF native backend routes all encoders through AAC/M4A and its stream entry uses the same file recorder. This implementation uses HarmonyOS AudioCapturer directly to provide actual PCM/WAV instead.
- Toolchain: Flutter `ohos/3.44.9+ohos-1.0.0-beta`. HarmonyOS API 17+ is the integration baseline; device acceptance is recorded below.

## Private publishing

Only this package is published. Its upload target is fixed by `publish_to`:
`https://nexus.pawrio.cn/repository/pub-private/`. Download/resolve through
`https://pub.pawrio.cn`.

```sh
cd /Users/weicheng/Documents/cn.pawrio/codex.workspace/pub.dev/record/record
export PUB_HOSTED_URL=https://pub.pawrio.cn
fvm flutter pub get --no-example
fvm dart pub publish --dry-run
fvm dart pub publish
```

Publish from a reviewed, clean Git commit. Run the standard preflight before
uploading and inspect any new warnings. Formal publishing is performed by the owner.

After publication, the App should pin `record: 7.1.2` while resolving through the
private download endpoint, so a later official release does not replace the
verified HarmonyOS implementation. Local path overrides are confined to isolated
validation projects. Generated native files, Flutter HARs and build output are
excluded from the package archive.

## HarmonyOS validation

- PCM implementation on HarmonyOS API 26: 8/16/48 kHz mono WAV with nonzero samples,
  exact RIFF/data lengths, dBFS amplitude, pause/resume, cancellation/deletion,
  PCM stream closure, repeated sessions, raw PCM and state events passed.
- App acceptance: recording overlay/waveform/progress, release/back cancellation,
  7.5 second cap, and human-to-pet server transcription into editable confirmation
  passed. Confirmation was cancelled; no translation message was submitted.
- Main package: 95 tests passed. App: 55 voice-flow and 102 input/command tests passed.
- Single-package hosted resolution, one automatic native registration from `record`,
  signed HarmonyOS HAP build, 95 main-package tests and Dart analysis passed.
- Private-target preflight verified the archive includes `ohos/` source and
  excludes its generated/build artifacts. Standard preflight is rerun after committing.
- Formal private publication and App dependency switch: pending the owner's release.

import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import {
  Any, AbilityAware, AbilityPluginBinding, BinaryMessenger, EventChannel, EventSink,
  FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel,
  MethodResult, StreamHandler
} from '@ohos/flutter_ohos';

class RecorderEvents implements StreamHandler {
  sink: EventSink | null = null;

  onListen(_arguments: Any, sink: EventSink): void {
    this.sink = sink;
  }

  onCancel(_arguments: Any): void {
    this.sink = null;
  }
}

class PcmRecorder {
  private capturer: audio.AudioCapturer | null = null;
  private file: fs.File | null = null;
  private path: string | null = null;
  private bytes: number = 0;
  private sampleRate: number = 48000;
  private channels: number = 1;
  private encoder: string = 'wav';
  private streaming: boolean = false;
  private active: boolean = false;
  private paused: boolean = false;
  private peak: number = -160;
  private maximum: number = -160;
  private writeError: Error | null = null;
  private readonly states: RecorderEvents = new RecorderEvents();
  private readonly chunks: RecorderEvents = new RecorderEvents();
  private readonly stateChannel: EventChannel;
  private readonly chunkChannel: EventChannel;

  constructor(messenger: BinaryMessenger, id: string) {
    this.stateChannel = new EventChannel(messenger, `com.llfbandit.record/events/${id}`);
    this.chunkChannel = new EventChannel(messenger, `com.llfbandit.record/eventsRecord/${id}`);
    this.stateChannel.setStreamHandler(this.states);
    this.chunkChannel.setStreamHandler(this.chunks);
  }

  async start(call: MethodCall, streaming: boolean): Promise<void> {
    const encoder = (call.argument('encoder') as string) ?? 'aacLc';
    if ((streaming && encoder !== 'pcm16bits') || (!streaming && encoder !== 'wav' && encoder !== 'pcm16bits')) {
      throw new Error('Supported encoders: wav/pcm16bits files and pcm16bits streams.');
    }
    const sampleRate = (call.argument('sampleRate') as number) ?? 44100;
    const channels = (call.argument('numChannels') as number) ?? 2;
    if (![8000, 16000, 32000, 44100, 48000].includes(sampleRate) || (channels !== 1 && channels !== 2)) {
      throw new Error('Unsupported PCM sample rate or channel count.');
    }
    if ((call.argument('device') as Any) !== null && (call.argument('device') as Any) !== undefined) {
      throw new Error('Selecting an input device is not supported.');
    }
    if ((call.argument('autoGain') as boolean) || (call.argument('echoCancel') as boolean) ||
      (call.argument('noiseSuppress') as boolean)) {
      throw new Error('Manual gain, echo cancellation and noise suppression are not supported.');
    }
    await this.stop(false);
    this.sampleRate = sampleRate;
    this.channels = channels;
    this.encoder = encoder;
    this.streaming = streaming;
    this.bytes = 0;
    this.peak = -160;
    this.maximum = -160;
    this.writeError = null;
    this.path = streaming ? null : (call.argument('path') as string);
    if (!streaming && !this.path) {
      throw new Error('An output path is required.');
    }
    const options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: sampleRate as audio.AudioSamplingRate,
        channels: channels as audio.AudioChannel,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    };
    try {
      if (this.path !== null) {
        this.file = fs.openSync(this.path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        if (encoder === 'wav') {
          this.writeAll(this.wavHeader(0));
        }
      }
      const capturer = await audio.createAudioCapturer(options);
      this.capturer = capturer;
      const actual = await capturer.getStreamInfo();
      if (actual.samplingRate !== sampleRate || actual.channels !== channels ||
        actual.sampleFormat !== audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE) {
        throw new Error('The device did not accept the requested PCM format.');
      }
      capturer.on('readData', (buffer: ArrayBuffer) => this.consume(buffer));
      capturer.on('audioInterrupt', (event: audio.InterruptEvent) => {
        if (event.forceType !== audio.InterruptForceType.INTERRUPT_FORCE) {
          return;
        }
        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
          this.paused = true;
          this.states.sink?.success(0);
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
          this.active = false;
          this.states.sink?.success(2);
          this.chunks.sink?.endOfStream();
        }
      });
      this.active = true;
      await capturer.start();
      this.states.sink?.success(1);
    } catch (error) {
      await this.stop(true);
      throw (error as Error);
    }
  }

  private consume(buffer: ArrayBuffer): void {
    if (!this.active || this.paused || this.writeError !== null) {
      return;
    }
    try {
      const samples = new DataView(buffer);
      let peak = 0;
      for (let i = 0; i + 1 < buffer.byteLength; i += 2) {
        peak = Math.max(peak, Math.abs(samples.getInt16(i, true)));
      }
      this.peak = peak === 0 ? -160 : 20 * Math.log10(peak / 32768);
      this.maximum = Math.max(this.maximum, this.peak);
      if (this.streaming) {
        this.chunks.sink?.success(new Uint8Array(buffer));
      } else {
        this.writeAll(buffer);
      }
      this.bytes += buffer.byteLength;
    } catch (error) {
      this.writeError = error as Error;
      this.states.sink?.error('record', 'Could not write PCM audio.', null);
    }
  }

  private writeAll(buffer: ArrayBuffer): void {
    if (this.file === null) {
      throw new Error('The output file is closed.');
    }
    let offset = 0;
    while (offset < buffer.byteLength) {
      const written = fs.writeSync(this.file.fd, buffer.slice(offset));
      if (written <= 0) {
        throw new Error('Could not write the output file.');
      }
      offset += written;
    }
  }

  private wavHeader(length: number): ArrayBuffer {
    if (length > 0xFFFFFFFF - 36) {
      throw new Error('The recording exceeds the WAV size limit.');
    }
    const buffer = new ArrayBuffer(44);
    const view = new DataView(buffer);
    const bytes = new Uint8Array(buffer);
    const tags = [82, 73, 70, 70, 87, 65, 86, 69, 102, 109, 116, 32, 100, 97, 116, 97];
    bytes.set(tags.slice(0, 4), 0);
    bytes.set(tags.slice(4, 12), 8);
    bytes.set(tags.slice(12), 36);
    view.setUint32(4, 36 + length, true);
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, this.channels, true);
    view.setUint32(24, this.sampleRate, true);
    view.setUint32(28, this.sampleRate * this.channels * 2, true);
    view.setUint16(32, this.channels * 2, true);
    view.setUint16(34, 16, true);
    view.setUint32(40, length, true);
    return buffer;
  }

  async stop(discard: boolean): Promise<string | null> {
    const capturer = this.capturer;
    const path = this.path;
    const hadCapture = capturer !== null;
    this.capturer = null;
    let failure: Error | null = this.writeError;
    try {
      if (capturer !== null) {
        if (capturer.state === audio.AudioState.STATE_RUNNING) {
          await capturer.stop();
        }
        capturer.off('readData');
        capturer.off('audioInterrupt');
        await capturer.release();
      }
    } catch (error) {
      failure = error as Error;
      if (capturer !== null && capturer.state !== audio.AudioState.STATE_RELEASED) {
        try { await capturer.release(); } catch (_) {}
      }
    } finally {
      this.active = false;
      this.paused = false;
      failure = failure ?? this.writeError;
      try {
        if (this.file !== null && this.encoder === 'wav' && !discard && failure === null) {
          fs.lseek(this.file.fd, 0, fs.WhenceType.SEEK_SET);
          this.writeAll(this.wavHeader(this.bytes));
          fs.fsyncSync(this.file.fd);
        }
      } catch (error) {
        failure = error as Error;
      } finally {
        if (this.file !== null) {
          fs.closeSync(this.file);
          this.file = null;
        }
        this.path = null;
        this.writeError = null;
        if (hadCapture) {
          this.states.sink?.success(2);
          if (this.streaming) { this.chunks.sink?.endOfStream(); }
        }
      }
      if (path !== null && (discard || failure !== null)) {
        try { fs.unlinkSync(path); } catch (_) {}
      }
    }
    if (failure !== null && !discard) { throw failure; }
    return discard ? null : path;
  }

  async pause(): Promise<void> {
    if (this.capturer !== null && this.active && !this.paused) {
      this.paused = true;
      try { await this.capturer.stop(); } catch (error) { this.paused = false; throw (error as Error); }
      this.states.sink?.success(0);
    }
  }

  async resume(): Promise<void> {
    if (this.capturer !== null && this.active && this.paused) {
      await this.capturer.start();
      this.paused = false;
      this.states.sink?.success(1);
    }
  }

  isRecording(): boolean { return this.active; }
  isPaused(): boolean { return this.active && this.paused; }
  amplitude(): Map<string, number> {
    const result = new Map<string, number>();
    result.set('current', this.active && !this.paused ? this.peak : -160);
    result.set('max', this.maximum);
    return result;
  }

  async dispose(): Promise<void> {
    await this.stop(true);
    this.stateChannel.setStreamHandler(null);
    this.chunkChannel.setStreamHandler(null);
    this.states.sink = null;
    this.chunks.sink = null;
  }
}

export default class RecordOhosPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private messenger: BinaryMessenger | null = null;
  private context: common.UIAbilityContext | null = null;
  private readonly recorders: Map<string, PcmRecorder> = new Map();
  private pending: Promise<void> = Promise.resolve();

  getUniqueClassName(): string { return 'PawrioRecordOhosPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.messenger = binding.getBinaryMessenger();
    this.channel = new MethodChannel(this.messenger, 'com.llfbandit.record/messages');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.pending = this.pending.then(async () => {
      for (const recorder of this.recorders.values()) { await recorder.dispose(); }
      this.recorders.clear();
      this.messenger = null;
    }).catch(() => {});
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void { this.context = null; }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.pending = this.pending.then(async () => {
      try { await this.handle(call, result); } catch (error) {
        const failure = error as BusinessError;
        result.error('record', failure.message ?? 'Audio recording failed.', null);
      }
    });
  }

  private async hasPermission(request: boolean): Promise<boolean> {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const manager = abilityAccessCtrl.createAtManager();
    if (manager.checkAccessTokenSync(info.appInfo.accessTokenId, 'ohos.permission.MICROPHONE') ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) { return true; }
    if (!request || this.context === null) { return false; }
    const response = await manager.requestPermissionsFromUser(this.context, ['ohos.permission.MICROPHONE']);
    return response.authResults.length > 0 && response.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    const id = (call.argument('recorderId') as string);
    if (!id) { throw new Error('recorderId is required.'); }
    if (call.method === 'create') {
      if (!this.recorders.has(id) && this.messenger !== null) {
        this.recorders.set(id, new PcmRecorder(this.messenger, id));
      }
      result.success(null);
      return;
    }
    const recorder = this.recorders.get(id);
    if (recorder === undefined) { throw new Error('The recorder has not been created.'); }
    switch (call.method) {
      case 'hasPermission': result.success(await this.hasPermission((call.argument('request') as boolean) ?? true)); break;
      case 'start':
      case 'startStream':
        if (!await this.hasPermission(false)) { throw new Error('Microphone permission is required.'); }
        await recorder.start(call, call.method === 'startStream');
        result.success(null);
        break;
      case 'stop': result.success(await recorder.stop(false)); break;
      case 'cancel': await recorder.stop(true); result.success(null); break;
      case 'dispose': await recorder.dispose(); this.recorders.delete(id); result.success(null); break;
      case 'pause': await recorder.pause(); result.success(null); break;
      case 'resume': await recorder.resume(); result.success(null); break;
      case 'isRecording': result.success(recorder.isRecording()); break;
      case 'isPaused': result.success(recorder.isPaused()); break;
      case 'getAmplitude': result.success(recorder.amplitude()); break;
      case 'listInputDevices': result.success([]); break;
      case 'isEncoderSupported':
        const encoder = (call.argument('encoder') as string);
        result.success(encoder === 'wav' || encoder === 'pcm16bits');
        break;
      default: result.notImplemented();
    }
  }
}

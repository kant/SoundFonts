// Copyright © 2020 Brad Howes. All rights reserved.

import AVFoundation
import CoreAudioKit
import SoundFontsFramework
import os

final class ReverbAU: AUAudioUnit {
  private let log: OSLog
  private let reverb = ReverbEffect()
  private lazy var audioUnit = reverb.audioUnit
  private lazy var wrapped = audioUnit.auAudioUnit

  private var _currentPreset: AUAudioUnitPreset?

  public private(set) lazy var parameters: AudioUnitParameters = AudioUnitParameters(
    parameterHandler: self)

  public init(componentDescription: AudioComponentDescription) throws {
    let log = Logging.logger("ReverbAU")
    self.log = log

    os_log(
      .debug, log: log, "init - flags: %d man: %d type: sub: %d",
      componentDescription.componentFlags, componentDescription.componentManufacturer,
      componentDescription.componentType, componentDescription.componentSubType)

    os_log(.debug, log: log, "starting AVAudioUnitSampler")

    do {
      try super.init(componentDescription: componentDescription, options: [])
    } catch {
      os_log(
        .error, log: log, "failed to initialize AUAudioUnit - %{public}s",
        error.localizedDescription)
      throw error
    }

    os_log(.debug, log: log, "init - done")
  }
}

extension ReverbAU: AUParameterHandler {

  public func set(_ parameter: AUParameter, value: AUValue) {
    switch AudioUnitParameters.Address(rawValue: parameter.address) {
    case .roomPreset:
      let index = min(max(Int(value), 0), ReverbEffect.roomPresets.count - 1)
      let preset = ReverbEffect.roomPresets[index]
      audioUnit.loadFactoryPreset(preset)
      reverb.active = reverb.active.setPreset(index)

    case .wetDryMix:
      audioUnit.wetDryMix = value
      reverb.active = reverb.active.setWetDryMix(value)

    default: break
    }
  }

  public func get(_ parameter: AUParameter) -> AUValue {
    switch AudioUnitParameters.Address(rawValue: parameter.address) {
    case .roomPreset: return AUValue(reverb.active.preset)
    case .wetDryMix: return audioUnit.wetDryMix
    default: return 0
    }
  }
}

extension ReverbAU {

  override public func supportedViewConfigurations(
    _ availableViewConfigurations: [AUAudioUnitViewConfiguration]
  ) -> IndexSet {
    IndexSet(availableViewConfigurations.indices)
  }

  override public var component: AudioComponent { wrapped.component }

  override public func allocateRenderResources() throws {
    os_log(.debug, log: log, "allocateRenderResources - %{public}d", outputBusses.count)
    for index in 0..<outputBusses.count {
      outputBusses[index].shouldAllocateBuffer = true
    }
    do {
      try wrapped.allocateRenderResources()
    } catch {
      os_log(
        .error, log: log, "allocateRenderResources failed - %{public}s", error.localizedDescription)
      throw error
    }
    os_log(.debug, log: log, "allocateRenderResources - done")
  }

  override public func deallocateRenderResources() {
    os_log(.debug, log: log, "deallocateRenderResources")
    wrapped.deallocateRenderResources()
  }

  override public var renderResourcesAllocated: Bool {
    os_log(.debug, log: log, "renderResourcesAllocated - %d", wrapped.renderResourcesAllocated)
    return wrapped.renderResourcesAllocated
  }

  override public func reset() {
    os_log(.debug, log: log, "reset")
    wrapped.reset()
    super.reset()
  }

  override public var inputBusses: AUAudioUnitBusArray {
    os_log(.debug, log: self.log, "inputBusses - %d", wrapped.inputBusses.count)
    return wrapped.inputBusses
  }

  override public var outputBusses: AUAudioUnitBusArray {
    os_log(.debug, log: self.log, "outputBusses - %d", wrapped.outputBusses.count)
    return wrapped.outputBusses
  }

  override public var scheduleParameterBlock: AUScheduleParameterBlock {
    os_log(.debug, log: self.log, "scheduleParameterBlock")
    return wrapped.scheduleParameterBlock
  }

  override public func token(byAddingRenderObserver observer: @escaping AURenderObserver) -> Int {
    os_log(.debug, log: self.log, "token by AddingRenderObserver")
    return wrapped.token(byAddingRenderObserver: observer)
  }

  override public func removeRenderObserver(_ token: Int) {
    os_log(.debug, log: self.log, "removeRenderObserver")
    wrapped.removeRenderObserver(token)
  }

  override public var maximumFramesToRender: AUAudioFrameCount {
    didSet { wrapped.maximumFramesToRender = self.maximumFramesToRender }
  }

  override public var parameterTree: AUParameterTree? {
    get {
      parameters.parameterTree
    }
    set {
      fatalError("setting parameterTree is unsupported")
    }
  }

  override public func parametersForOverview(withCount count: Int) -> [NSNumber] {
    os_log(.debug, log: log, "parametersForOverview: %d", count)
    return [NSNumber(value: parameters.wetDryMix.address)]
  }

  override public var allParameterValues: Bool { wrapped.allParameterValues }
  override public var isMusicDeviceOrEffect: Bool { true }

  override public var virtualMIDICableCount: Int {
    os_log(.debug, log: self.log, "virtualMIDICableCount - %d", wrapped.virtualMIDICableCount)
    return wrapped.virtualMIDICableCount
  }

  override public var midiOutputNames: [String] { wrapped.midiOutputNames }

  override public var midiOutputEventBlock: AUMIDIOutputEventBlock? {
    get { wrapped.midiOutputEventBlock }
    set { wrapped.midiOutputEventBlock = newValue }
  }

  override public var fullState: [String: Any]? {
    get { reverb.active.fullState }
    set {
      guard let fullState = newValue,
            let config = ReverbConfig(state: fullState)
      else { return }
      reverb.active = config
      parameters.set(.roomPreset, value: AUValue(config.preset), originator: nil)
      parameters.set(.wetDryMix, value: config.wetDryMix, originator: nil)
    }
  }

  override public var fullStateForDocument: [String: Any]? {
    get {
      var state = fullState ?? [String: Any]()
      if let preset = _currentPreset {
        state[kAUPresetNameKey] = preset.name
        state[kAUPresetNumberKey] = preset.number
      }
      state[kAUPresetDataKey] = Data()
      state[kAUPresetTypeKey] = FourCharCode(stringLiteral: "aufx")
      state[kAUPresetSubtypeKey] = FourCharCode(stringLiteral: "revb")
      state[kAUPresetManufacturerKey] = FourCharCode(stringLiteral: "bray")
      state[kAUPresetVersionKey] = FourCharCode(67072)
      return state
    }
    set { fullState = newValue }
  }

  override var supportsUserPresets: Bool { true }

  public override var factoryPresets: [AUAudioUnitPreset] { reverb.factoryPresets }

  override var currentPreset: AUAudioUnitPreset? {
    get { _currentPreset }
    set {
      guard let preset = newValue else {
        _currentPreset = nil
        return
      }

      if preset.number >= 0 {
        if preset.number < reverb.factoryPresetConfigs.count {
          let config = reverb.factoryPresetConfigs[preset.number]
          parameters.setConfig(config)
          _currentPreset = preset
        }
      } else {
        if #available(iOS 13.0, *) {
          if let fullState = try? presetState(for: preset) {
            self.fullState = fullState
            _currentPreset = preset
          }
        }
      }
    }
  }

  override public var latency: TimeInterval { wrapped.latency }
  override public var tailTime: TimeInterval { wrapped.tailTime }

  override public var renderQuality: Int {
    get { wrapped.renderQuality }
    set { wrapped.renderQuality = newValue }
  }

  override public var channelCapabilities: [NSNumber]? { wrapped.channelCapabilities }

  override public var channelMap: [NSNumber]? {
    get { wrapped.channelMap }
    set { wrapped.channelMap = newValue }
  }

  override public func profileState(forCable cable: UInt8, channel: MIDIChannelNumber)
  -> MIDICIProfileState
  {
    wrapped.profileState(forCable: cable, channel: channel)
  }

  override public var canPerformInput: Bool { wrapped.canPerformInput }

  override public var canPerformOutput: Bool { wrapped.canPerformOutput }

  override public var isInputEnabled: Bool {
    get { wrapped.isInputEnabled }
    set { wrapped.isInputEnabled = newValue }
  }

  override public var isOutputEnabled: Bool {
    get { wrapped.isOutputEnabled }
    set { wrapped.isOutputEnabled = newValue }
  }

  override public var outputProvider: AURenderPullInputBlock? {
    get { wrapped.outputProvider }
    set { wrapped.outputProvider = newValue }
  }

  override public var inputHandler: AUInputHandler? {
    get { wrapped.inputHandler }
    set { wrapped.inputHandler = newValue }
  }

  override public var isRunning: Bool { wrapped.isRunning }

  override public func startHardware() throws {
    os_log(.debug, log: self.log, "startHardware")
    do {
      try wrapped.startHardware()
    } catch {
      os_log(.error, log: self.log, "startHardware failed - %s", error.localizedDescription)
      throw error
    }
    os_log(.debug, log: self.log, "startHardware - done")
  }

  override public func stopHardware() { wrapped.stopHardware() }

  override public var scheduleMIDIEventBlock: AUScheduleMIDIEventBlock? {
    let block = self.wrapped.scheduleMIDIEventBlock
    let log = self.log
    return { (when: AUEventSampleTime, channel: UInt8, count: Int, bytes: UnsafePointer<UInt8>) in
      os_log(
        .debug, log: log,
        "scheduleMIDIEventBlock - when: %d chan: %d count: %d cmd: %d arg1: %d, arg2: %d",
        when, channel, count, bytes[0], bytes[1], bytes[2])
      block?(when, channel, count, bytes)
    }
  }

  override public var renderBlock: AURenderBlock { wrapped.renderBlock }

  override var internalRenderBlock: AUInternalRenderBlock {

    // Local copy of values that will be used in render block. Must not dispatch or allocate memory in the block.
    let wrappedBlock = wrapped.internalRenderBlock
    let roomPresetParameter = parameters.roomPreset
    let wetDryMixParameter = parameters.wetDryMix

    return {
      (
        actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead,
        pullInputBlock
      ) in
      var head = realtimeEventListHead
      while head != nil {
        guard let event = head?.pointee else { break }
        if event.head.eventType == .parameter {
          let address = event.parameter.parameterAddress
          let value = event.parameter.value
          switch AudioUnitParameters.Address(rawValue: address) {
          case .roomPreset: roomPresetParameter.setValue(value, originator: nil)
          case .wetDryMix: wetDryMixParameter.setValue(value, originator: nil)
          default: break
          }
        }
        head = UnsafePointer<AURenderEvent>(event.head.next)
      }
      return wrappedBlock(
        actionFlags, timestamp, frameCount, outputBusNumber, outputData, head, pullInputBlock)
    }
  }
}

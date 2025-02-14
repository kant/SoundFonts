// Copyright © 2020 Brad Howes. All rights reserved.

import AudioUnit
import SoundFontsFramework
import os

/// Definitions for the runtime parameters of the audio unit.
public struct AudioUnitParameters {
  private let log = Logging.logger("AudioUnitParameters")

  enum Address: AUParameterAddress {
    case time = 1
    case feedback
    case cutoff
    case wetDryMix
  }

  public let time: AUParameter = {
    let param = AUParameterTree.createParameter(
      withIdentifier: "time", name: "Time", address: Address.time.rawValue, min: 0.0, max: 2.0, unit: .seconds,
      unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil, dependentParameters: nil)
    param.value = 1.0
    return param
  }()

  public let feedback: AUParameter = {
    let param = AUParameterTree.createParameter(
      withIdentifier: "feedback", name: "Feedback", address: Address.feedback.rawValue, min: -100.0, max: 100.0,
      unit: .percent, unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil,
      dependentParameters: nil)
    param.value = 50.0
    return param
  }()

  public let cutoff: AUParameter = {
    let param = AUParameterTree.createParameter(
      withIdentifier: "cutoff", name: "Cutoff", address: Address.cutoff.rawValue, min: 10.0, max: 20_000.0,
      unit: .hertz, unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable, .flag_DisplayLogarithmic],
      valueStrings: nil, dependentParameters: nil)
    param.value = 18_000.0
    return param
  }()

  public let wetDryMix: AUParameter = {
    let param = AUParameterTree.createParameter(
      withIdentifier: "wetDryMix", name: "Mix", address: Address.wetDryMix.rawValue, min: 0.0, max: 100.0,
      unit: .percent, unitName: nil, flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil,
      dependentParameters: nil)
    param.value = 30.0
    return param
  }()

  /// AUParameterTree created with the parameter definitions for the audio unit
  public let parameterTree: AUParameterTree

  /**
   Create a new AUParameterTree for the defined filter parameters.

   Installs three closures in the tree:
   - one for providing values
   - one for accepting new values from other sources
   - and one for obtaining formatted string values

   - parameter parameterHandler the object to use to handle the AUParameterTree requests
   */
  public init(parameterHandler: AUParameterHandler) {

    // Define a new parameter tree with the parameter definitions
    parameterTree = AUParameterTree.createTree(withChildren: [time, feedback, cutoff, wetDryMix])

    // Provide a way for the tree to change values in the AudioUnit
    parameterTree.implementorValueObserver = parameterHandler.set

    // Provide a way for the tree to obtain the current value of a parameter from the AudioUnit
    parameterTree.implementorValueProvider = parameterHandler.get

    // Provide a way to obtain String values for the current settings.
    let log = self.log
    parameterTree.implementorStringFromValueCallback = { param, value in
      let formatted: String = {
        switch Address(rawValue: param.address) {
        case .time: return String(format: "%.2f", param.value) + "s"
        case .feedback: return String(format: "%.2f", param.value) + "%"
        case .cutoff: return String(format: "%.2f", param.value) + "Hz"
        case .wetDryMix: return String(format: "%.2f", param.value) + "%"
        default: return "?"
        }
      }()
      os_log(.debug, log: log, "parameter %d as string: %d %f %{public}s", param.address, param.value, formatted)
      return formatted
    }
  }

  func setConfig(_ config: DelayConfig) {
    os_log(.debug, log: log, "setConfig")
    self.time.setValue(config.time, originator: nil)
    self.feedback.setValue(config.feedback, originator: nil)
    self.cutoff.setValue(config.cutoff, originator: nil)
    self.wetDryMix.setValue(config.wetDryMix, originator: nil)
  }

  func set(_ address: Address, value: AUValue, originator: AUParameterObserverToken?) {
    switch address {
    case .time: time.setValue(value, originator: originator)
    case .feedback: feedback.setValue(value, originator: originator)
    case .cutoff: cutoff.setValue(value, originator: originator)
    case .wetDryMix: wetDryMix.setValue(value, originator: originator)
    }
  }
}

extension AUParameterTree {

  func parameter(withAddress: AudioUnitParameters.Address) -> AUParameter? {
    parameter(withAddress: withAddress.rawValue)
  }
}

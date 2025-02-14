// Copyright © 2020 Brad Howes. All rights reserved.

import AVFoundation

public struct ChorusConfig: Codable {

  public enum Key: String, CaseIterable {
    case enabled
    case rate
    case delay
    case depth
    case feedback
    case wetDryMix
    case negFeedback
    case odd90
  }

  public let enabled: Bool
  public let rate: AUValue
  public let delay: AUValue
  public let depth: AUValue
  public let feedback: AUValue
  public let wetDryMix: AUValue
  public let negFeedback: Bool
  public let odd90: Bool
}

extension ChorusConfig {

  public init(settings: Settings) {
    self.init(
      enabled: settings.chorusEnabled,
      rate: settings.chorusRate,
      delay: settings.chorusDelay,
      depth: settings.chorusDepth,
      feedback: settings.chorusFeedback,
      wetDryMix: settings.chorusWetDryMix,
      negFeedback: settings.chorusNegFeedback,
      odd90: settings.chorusOdd90)
  }

  public init?(state: [String: Any]) {
    guard let enabled = state[.enabled] == 0.0 ? false : true,
          let rate = state[.rate],
          let delay = state[.delay],
          let depth = state[.depth],
          let feedback = state[.feedback],
          let wetDryMix = state[.wetDryMix],
          let negFeedback = state[.negFeedback] == 0.0 ? false : true,
          let odd90 = state[.odd90] == 0.0 ? false : true
    else { return nil }
    self.init(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }

  public func setEnabled(_ enabled: Bool) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setRate(_ rate: Float) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setDelay(_ delay: Float) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setDepth(_ depth: Float) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setFeedback(_ feedback: Float) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setWetDryMix(_ wetDryMix: Float) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setNegFeedback(_ negFeedback: Bool) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }
  public func setOdd90(_ odd90: Bool) -> ChorusConfig {
    ChorusConfig(
      enabled: enabled, rate: rate, delay: delay, depth: depth, feedback: feedback, wetDryMix: wetDryMix,
      negFeedback: negFeedback, odd90: odd90)
  }

  public subscript(_ key: Key) -> AUValue {
    switch key {
    case .enabled: return AUValue(enabled ? 1.0 : 0.0)
    case .rate: return rate
    case .delay: return delay
    case .depth: return depth
    case .feedback: return feedback
    case .wetDryMix: return wetDryMix
    case .negFeedback: return AUValue(negFeedback ? 1.0 : 0.0)
    case .odd90: return AUValue(odd90 ? 1.0 : 0.0)
    }
  }

  public var fullState: [String: Any] {
    [String: Any](
      uniqueKeysWithValues: zip(Key.allCases.map { $0.rawValue }, Key.allCases.map { self[$0] }))
  }
}

extension ChorusConfig: CustomStringConvertible {
  public var description: String {
    "<Chorus \(enabled) \(rate) \(delay) \(depth) \(feedback) \(wetDryMix) \(negFeedback) \(odd90)>"
  }
}

extension Dictionary where Key == String, Value == Any {
  fileprivate subscript(_ key: ChorusConfig.Key) -> AUValue? { self[key.rawValue] as? AUValue }
}

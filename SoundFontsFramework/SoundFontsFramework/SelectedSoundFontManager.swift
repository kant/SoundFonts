// Copyright © 2018 Brad Howes. All rights reserved.

import Foundation
import os

public enum SelectedSoundFontEvent {
  case changed(old: SoundFont?, new: SoundFont?)
}

public final class SelectedSoundFontManager: SubscriptionManager<SelectedSoundFontEvent> {
  private lazy var log = Logging.logger("SelectedSoundFontManager")

  public private(set) var selected: SoundFont?

  public init() {
    super.init()
    os_log(.info, log: log, "selected: %{public}s %{public}s", selected?.displayName ?? "nil",
           String.pointer(selected))
  }

  public func setSelected(_ soundFont: SoundFont) {
    os_log(.info, log: log, "setSelected: %{public}s %{public}s", soundFont.displayName, String.pointer(soundFont))
    guard selected != soundFont else {
      os_log(.info, log: log, "already active")
      return
    }

    let old = selected
    selected = soundFont
    notify(.changed(old: old, new: soundFont))
  }

  public func clearSelected() {
    guard selected != nil else { return }
    let old = selected
    selected = nil
    notify(.changed(old: old, new: nil))
  }
}
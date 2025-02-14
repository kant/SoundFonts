// Copyright © 2018 Brad Howes. All rights reserved.

import UIKit

/// Mapping of UITouch instances from touch events to the Key instances that are played by the touches.
internal struct TouchKeyMap {

  /// The sampler that is generating sound
  var processor: NoteProcessor?

  private var touchedKeys = [UITouch: Key]()

  /**
   Remove all assignments.
   */
  mutating func releaseAll() {
    touchedKeys.forEach { keyRelease($0.1) }
    touchedKeys.removeAll()
  }

  /**
   Release any key that is attached to the given touch.

   - parameter touch: the touch to remove
   */
  mutating func release(_ touch: UITouch) {
    guard let key = touchedKeys[touch] else { return }
    keyRelease(key)
    touchedKeys.removeValue(forKey: touch)
  }

  /**
   Assign a key to the given touch. If the touch is already assigned, release the previous assignment.

   - parameter touch: the touch to attach to
   - parameter key: the key to press
   - returns: true if a new note was started
   */
  mutating func assign(_ touch: UITouch, key: Key) -> Bool {
    if let previous = touchedKeys[touch] {
      guard previous.note != key.note else { return false }
      keyRelease(previous)
    }

    keyPress(key)
    touchedKeys[touch] = key
    return true
  }
}

extension TouchKeyMap {

  private func keyPress(_ key: Key) {
    key.pressed = true
    processor?.noteOn(UInt8(key.note.midiNoteValue), velocity: 64)
  }

  private func keyRelease(_ key: Key) {
    key.pressed = false
    processor?.noteOff(UInt8(key.note.midiNoteValue))
  }
}

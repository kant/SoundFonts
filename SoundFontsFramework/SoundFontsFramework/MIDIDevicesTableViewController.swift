// Copyright © 2021 Brad Howes. All rights reserved.

import UIKit
import CoreMIDI

/**
 A table view that shows the known MIDI devices.
 */
final class MIDIDevicesTableViewController: UITableViewController, Tasking {

  private var devices = [MIDI.DeviceState]() { didSet { self.tableView.reloadData() } }
  private var activeConnectionsObserver: NSKeyValueObservation?
  private var channelsObserver: NSKeyValueObservation?

  func setDevices(_ devices: [MIDI.DeviceState]) {
    self.devices = devices
  }
}

// MARK: - View Management

extension MIDIDevicesTableViewController {

  override public func viewDidLoad() {
    activeConnectionsObserver = MIDI.sharedInstance.observe(\.activeConnections) { [weak self] _, _ in
      self?.devices = MIDI.sharedInstance.devices
    }
    channelsObserver = MIDI.sharedInstance.observe(\.channels) { [weak self] _, _ in
      Self.onMain {
        self?.tableView.reloadData()
      }
    }
    super.viewDidLoad()
  }

  override public func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    MIDI.sharedInstance.monitor = self
  }

  override public func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if let monitor = MIDI.sharedInstance.monitor, monitor === self {
      MIDI.sharedInstance.monitor = nil
    }
  }
}

// MARK: - Table View Methods

extension MIDIDevicesTableViewController {

  override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    devices.count
  }

  override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "deviceState", for: indexPath)
    let deviceState = devices[indexPath.row]
    cell.textLabel?.text = deviceState.displayName

    let channel = MIDI.sharedInstance.channels[deviceState.uniqueId] ?? -2
    let channelText = channel == -2 ? "" : "Chan: \(channel + 1)"
    cell.detailTextLabel?.text = "\(channelText)" // "\(deviceState.connected ? "✅" : "🟥")"
    return cell
  }

  @IBAction func resetMIDI(_ sender: Any) {
    MIDIRestart()
  }
}

// MARK: - MIDIMonitor Methods

extension MIDIDevicesTableViewController: MIDIMonitor {

  public func seen(uniqueId: MIDIUniqueID, channel: Int) {
    Self.onMain {
      for (row, deviceState) in self.devices.enumerated() where deviceState.uniqueId == uniqueId {
        let indexPath = IndexPath(row: row, section: 0)
        if let cell = self.tableView.cellForRow(at: indexPath) {
          let layer = cell.contentView.layer
          Self.midiSeenLayerChange(layer)
        }
      }
    }
  }

  public static func midiSeenLayerChange(_ layer: CALayer) {
    let color = UIColor.systemOrange.cgColor
    let animator = CABasicAnimation(keyPath: "backgroundColor")
    animator.fromValue = color
    animator.toValue = UIColor.clear.cgColor
    layer.add(animator, forKey: "MIDI Seen")
  }
}

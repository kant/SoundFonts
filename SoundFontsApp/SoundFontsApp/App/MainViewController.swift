// Copyright © 2018 Brad Howes. All rights reserved.

import AVKit
import SoundFontsFramework
import UIKit
import os

/**
 Top-level view controller for the application. It contains the Sampler which will emit sounds based on what keys are
 touched. It also starts the audio engine when the application becomes active, and stops it when the application goes
 to the background or stops being active.
 */
final class MainViewController: UIViewController, Tasking {
  private lazy var log = Logging.logger("MainViewController")

  private weak var router: ComponentContainer?
  private var midiController: MIDIController?
  private var soundFonts: SoundFonts!
  private var activePresetManager: ActivePresetManager!
  private var keyboard: Keyboard!
  private var sampler: Sampler?
  private var infoBar: InfoBar!
  private var settings: Settings!
  fileprivate var noteInjector: NoteInjector!

  private var startRequested = false
  private var volumeMonitor: VolumeMonitor?
  private var observers = [NSObjectProtocol]()
#if TEST_MEDIA_SERVICES_RESTART
  private var resetTimers = [Timer]()
#endif

  /// Disable system gestures near screen edges so that touches on the keyboard are always seen by the application.
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
    return [.left, .right, .bottom]
  }

  /// If true, do not show the tutorial pages for the first time the application starts. This is used by the UI tests.
  /// It is set by `AppDelegate` to true when "-ui_testing" is present on the command line.
  var skipTutorial = false

  override func viewDidLoad() {
    super.viewDidLoad()
    UIApplication.shared.appDelegate.setMainViewController(self)
    setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    observers.append(NotificationCenter.default.addObserver(forName: .showTutorial, object: nil,
                                                            queue: nil) { [weak self] _ in
      self?.showTutorial()
    })

    observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                                            object: nil, queue: nil) { [weak self] _ in
      self?.recreateSampler()
    })
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !skipTutorial && !settings.showedTutorial {
      showTutorial()
      settings.showedTutorial = true
    }

    // When enabled, start a timer that will trigger a notification to force the audio system to restart.
#if TEST_MEDIA_SERVICES_RESTART
    resetTimers.append(Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
      NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    })
#endif
  }

  override func willTransition(to newCollection: UITraitCollection,
                               with coordinator: UIViewControllerTransitionCoordinator) {
    super.willTransition(to: newCollection, with: coordinator)
    coordinator.animate(
      alongsideTransition: { _ in
        InfoHUD.clear()
      },
      completion: { _ in
        self.volumeMonitor?.repostNotice()
      })
  }
}

extension MainViewController {

  /**
   Show the changes screen if there are changes to be shown.
   */
  func showChanges() {
    let currentVersion = Bundle.main.releaseVersionNumber
    if settings.showedChanges != currentVersion {
      let changes = ChangesCompiler.compile(since: settings.showedChanges)
      settings.showedChanges = currentVersion
      if let viewController = TutorialViewController.instantiateChanges(changes) {
        present(viewController, animated: true, completion: nil)
      }
    }
  }

  /**
   Show the tutorial screens.
   */
  func showTutorial() {
    os_log(.debug, log: log, "showTuorial")
    if let viewController = TutorialViewController.instantiate() {
      present(viewController, animated: true, completion: nil)
    }
  }

  /**
   Start audio processing. This is done as the app is brought into the foreground.
   */
  func startAudio() {
    os_log(.debug, log: log, "startAudio BEGIN")
    startRequested = true
    guard let sampler = self.sampler else {
      os_log(.debug, log: log, "startAudio END - no sampler")
      return
    }

    Self.onBackground { self.startAudioBackground_BT(sampler) }
    os_log(.debug, log: log, "startAudio END")
  }

  @objc func handleRouteChange_BT(notification: Notification) {
    os_log(.debug, log: log, "handleRouteChange_BT BEGIN")
    guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else {
      os_log(.debug, log: log, "handleRouteChange_BT END - nothing to see")
      return
    }

    // Switch over the route change reason.
    switch reason {

    case .newDeviceAvailable: // New device found.
      os_log(.debug, log: log, "handleRouteChange_BT - new device available")
      let session = AVAudioSession.sharedInstance()
      dump(route: session.currentRoute)

    case .oldDeviceUnavailable: // Old device removed.
      os_log(.debug, log: log, "handleRouteChange_BT - old device unavailable")
      let session = AVAudioSession.sharedInstance()
      if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
        dump(route: previousRoute)
        dump(route: session.currentRoute)
      }

    default:
      os_log(.debug, log: log, "handleRouteChange_BT - AVAudioSession.unknown reason - %d", reason.rawValue)
    }
    os_log(.debug, log: log, "handleRouteChange_BT END")
  }

  /**
   Stop audio processing. This is done prior to the app moving into the background.
   */
  func stopAudio() {
    os_log(.debug, log: log, "stopAudio BEGIN")
    startRequested = false
    guard sampler != nil else {
      os_log(.debug, log: log, "stopAudio END - no sampler")
      return
    }

    MIDI.sharedInstance.receiver = nil
    volumeMonitor?.stop()
    sampler?.stop()

    let session = AVAudioSession.sharedInstance()
    do {
      os_log(.debug, log: log, "stopAudio - setting AudioSession to inactive")
      try session.setActive(false, options: [])
      os_log(.debug, log: log, "stopAudio - done")
    } catch let error as NSError {
      os_log(.error, log: log, "stopAudio - Failed session.setActive(false): %{public}s", error.localizedDescription)
    }

    os_log(.debug, log: log, "stopAudio END")
  }
}

// MARK: - Controller Configuration

extension MainViewController: ControllerConfiguration {

  private func startAudioBackground_BT(_ sampler: Sampler) {
    os_log(.debug, log: log, "startAudioBackground_BT BEGIN")

    let sampleRate: Double = 44100.0
    let bufferSize: Int = 512
    let session = AVAudioSession.sharedInstance()

    setupAudioSessionNotifications_BT()

    do {
      os_log(.debug, log: log, "startAudioBackground_BT - setting AudioSession category")
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
      os_log(.debug, log: log, "startAudioBackground_BT - done")
    } catch let error as NSError {
      os_log(.error, log: log,
             "startAudioBackground_BT - failed to set the audio session category and mode: %{public}s",
             error.localizedDescription)
    }

    os_log(.debug, log: log, "startAudioBackground_BT - sampleRate: %f", AVAudioSession.sharedInstance().sampleRate)
    os_log(.debug, log: log, "startAudioBackground_BT - preferredSampleRate: %f",
           AVAudioSession.sharedInstance().sampleRate)

    do {
      os_log(.debug, log: log, "startAudioBackground_BT - setting sample rate")
      try session.setPreferredSampleRate(sampleRate)
      os_log(.debug, log: log, "startAudioBackground_BT - done")
    } catch let error as NSError {
      os_log(.error, log: log, "startAudioBackground_BT - failed to set the preferred sample rate to %f: %{public}s",
             sampleRate, error.localizedDescription)
    }

    do {
      os_log(.debug, log: log, "startAudioBackground_BT - setting IO buffer duration")
      try session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
      os_log(.debug, log: log, "startAudioBackground_BT - done")
    } catch let error as NSError {
      os_log(.error, log: log, "startAudioBackground_BT - failed to set the preferred buffer size to %d: %{public}s",
             bufferSize, error.localizedDescription)
    }

    do {
      os_log(.debug, log: log, "startAudioBackground_BT - setting active audio session")
      try session.setActive(true, options: [])
      os_log(.debug, log: log, "startAudioBackground_BT - done")
    } catch {
      os_log(.error, log: log, "startAudioBackground_BT - failed to set active", error.localizedDescription)
    }

    dump(route: session.currentRoute)

    os_log(.debug, log: log, "startAudioBackground_BT - starting sampler")
    let result = sampler.start()

    Self.onMain { self.finishStart(result) }
    os_log(.debug, log: log, "startAudioBackground_BT END")
  }

  /**
   Establish connections with other managers / controllers.

   - parameter router: the ComponentContainer that holds all of the registered managers / controllers
   */
  func establishConnections(_ router: ComponentContainer) {
    os_log(.debug, log: log, "establishConnections BEGIN")
    self.router = router

    soundFonts = router.soundFonts
    infoBar = router.infoBar
    keyboard = router.keyboard
    activePresetManager = router.activePresetManager
    settings = router.settings
    noteInjector = .init(settings: settings)

    #if !targetEnvironment(macCatalyst)
    volumeMonitor = VolumeMonitor(keyboard: router.keyboard)
    #endif

    router.activePresetManager.subscribe(self, notifier: activePresetChanged_BT)
    router.subscribe(self, notifier: routerChanged_BT)
    if let sampler = router.sampler {
      activePresetManager.runOnNotifyQueue { self.setSampler_BT(sampler) }
    }
    
    activePresetManager.restoreActive(settings.lastActivePreset)

    os_log(.debug, log: log, "establishConnections END")
  }

  private func startMIDI() {
    os_log(.debug, log: log, "startMIDI BEGIN")
    guard let sampler = self.sampler else { return }
    os_log(.error, log: log, "starting MIDI for sampler")
    midiController = MIDIController(sampler: sampler, keyboard: keyboard, settings: settings)
    MIDI.sharedInstance.receiver = midiController
    os_log(.debug, log: log, "startMIDI END")
  }

  private func routerChanged_BT(_ event: ComponentContainerEvent) {
    os_log(.debug, log: log, "routerChanged: %{public}s", event.description)
    switch event {
    case .samplerAvailable(let sampler): setSampler_BT(sampler)
    }
  }

  private func setSampler_BT(_ sampler: Sampler) {
    os_log(.debug, log: log, "setSampler_BT BEGIN")
    self.sampler = sampler
    if startRequested {
      self.startAudioBackground_BT(sampler)
    }
    os_log(.debug, log: log, "setSampler_BT END")
  }

  private func activePresetChanged_BT(_ event: ActivePresetEvent) {
    os_log(.debug, log: log, "activePresetChanged_BT BEGIN - %{public}s", event.description)
    if case let .change(old: _, new: new, playSample: playSample) = event {
      useActivePreset_BT(new, playSample: playSample)
    }
    os_log(.debug, log: log, "activePresetChanged_BT END")
  }

  private func useActivePreset_BT(_ activePresetKind: ActivePresetKind, playSample: Bool) {
    os_log(.debug, log: log, "useActivePreset_BT BEGIN - %{public}s", activePresetKind.description)
    volumeMonitor?.validActivePreset = activePresetKind != .none
    midiController?.allNotesOff()
    guard let sampler = self.sampler else { return }
    let result = sampler.loadActivePreset {
      if playSample { self.noteInjector.post(to: sampler) }
    }

    if case let .failure(what) = result, what != .noSampler {
      self.postAlert_BT(for: what)
    }

    os_log(.debug, log: log, "useActivePreset_BT END")
  }

  private func finishStart(_ result: Sampler.StartResult) {
    os_log(.debug, log: log, "finishStart BEGIN - %{public}s", result.description)

    switch result {
    case let .failure(what):
      os_log(.debug, log: log, "finishStart - failed to start audio session")
      postAlert_BT(for: what)
    case .success:
      os_log(.debug, log: log, "finishStart - starting volumeMonitor and MIDI")
      volumeMonitor?.start()
      startMIDI()
    }
    os_log(.error, log: log, "finishStart - END")
  }

  private func recreateSampler() {
    os_log(.error, log: log, "recreateSampler - BEGIN")
    self.stopAudio()
    self.sampler = nil
    router?.createAudioComponents()
    self.startAudio()
    os_log(.error, log: log, "recreateSampler - END")
  }

  private func postAlert_BT(for what: SamplerStartFailure) {
    Self.onMain {
      NotificationCenter.default.post(Notification(name: .samplerStartFailure, object: what))
    }
  }

  private func setupAudioSessionNotifications_BT() {
    NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange_BT),
                                           name: AVAudioSession.routeChangeNotification, object: nil)
  }

  private func dump(route: AVAudioSessionRouteDescription) {
    for input in route.inputs {
      os_log(.debug, log: log, "AVAudioSession input - %{public}s", input.portName)
    }
    for output in route.outputs {
      os_log(.debug, log: log, "AVAudioSession output - %{public}s", output.portName)
    }
  }
}

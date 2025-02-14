// Copyright © 2018 Brad Howes. All rights reserved.

import UIKit

/// Collection of UIViewControllers and protocol facades which helps establish inter-controller relationships during the
/// application launch. Each view controller is responsible for establishing the connections in their
/// `establishConnections` method. The goal should be to have relations between a controller and protocols / facades, and
/// not between controllers themselves. This is enforced here through access restrictions to known controllers.
public final class Components<T: UIViewController>: SubscriptionManager<ComponentContainerEvent>, ComponentContainer
where T: ControllerConfiguration {
  private let accessQueue = DispatchQueue(label: "ComponentsQueue", qos: .background, attributes: [],
                                          autoreleaseFrequency: .inherit, target: .global(qos: .background))
  public let settings: Settings
  /// The configuration file that defines what fonts are installed and customizations
  public let consolidatedConfigProvider: ConsolidatedConfigProvider
  /// The unique identity associated with this instance (app or AUv3)
  public var identity: Int { consolidatedConfigProvider.identity }
  /// Manager that controls when to ask for a review from the customer
  public let askForReview: AskForReview?
  /// The manager for the collection of sound fonts
  public let soundFonts: SoundFonts
  /// The manager for the collection of favorites
  public let favorites: Favorites
  /// The manager for the collection of sound font tags
  public let tags: Tags
  /// The manager of the active preset
  public let activePresetManager: ActivePresetManager
  /// The manager of the selected sound font
  public let selectedSoundFontManager: SelectedSoundFontManager
  /// The manager of the active tag for font filtering
  public let activeTagManager: ActiveTagManager

  /// True if running in the app; false when running in the AUv3 app extension
  public let inApp: Bool
  /// The main view controller of the app
  public private(set) weak var mainViewController: T! { didSet { oneTimeSet(oldValue) } }

  private weak var soundFontsControlsController: SoundFontsControlsController! { didSet { oneTimeSet(oldValue) } }
  private weak var soundFontsViewController: SoundFontsViewController! { didSet { oneTimeSet(oldValue) } }
  private weak var infoBarController: InfoBarController! { didSet { oneTimeSet(oldValue) } }
  private weak var keyboardController: KeyboardController? { didSet { oneTimeSet(oldValue) } }
  private weak var favoritesController: FavoritesViewController! { didSet { oneTimeSet(oldValue) } }
  private weak var guideController: GuideViewController! { didSet { oneTimeSet(oldValue) } }
  private weak var effectsController: EffectsController? { didSet { oneTimeSet(oldValue) } }
  private weak var fontsTableViewController: FontsTableViewController! { didSet { oneTimeSet(oldValue) } }
  private weak var presetsTableViewController: PresetsTableViewController! { didSet { oneTimeSet(oldValue) } }
  private weak var tagsTableViewController: TagsTableViewController! { didSet { oneTimeSet(oldValue) } }

  /// The controller for the info bar
  public var infoBar: InfoBar { infoBarController }

  /// The controller for the keyboard (nil when running in the AUv3 app extension)
  public var keyboard: Keyboard? { keyboardController }

  /// The manager of the fonts/presets view
  public var fontsViewManager: FontsViewManager { soundFontsViewController }

  /// The manager of the favorites view
  public var favoritesViewManager: FavoritesViewManager { favoritesController }

  /// Swipe actions generator for sound font rows
  public var fontSwipeActionGenerator: FontActionManager { soundFontsViewController }

  /// The manager for posting alerts
  public var alertManager: AlertManager { accessQueue.sync { _alertManager! } }

  /// The sampler engine that generates audio from sound font files
  public var sampler: Sampler? { accessQueue.sync { _sampler } }

  private var _alertManager: AlertManager?

  private var _sampler: Sampler? {
    didSet {
      if let sampler = _sampler {
        notify(.samplerAvailable(sampler))
      }
    }
  }

  /**
   Create a new instance

   - parameter inApp: true if running in the app, false if running as audio unit
   */
  public init(inApp: Bool) {
    self.inApp = inApp
    self.settings = Settings()

    self.consolidatedConfigProvider = .init(inApp: inApp)

    self.askForReview = inApp ? AskForReview(settings: settings) : nil

    self.soundFonts = SoundFontsManager(consolidatedConfigProvider, settings: settings)
    self.favorites = FavoritesManager(consolidatedConfigProvider)
    self.tags = TagsManager(consolidatedConfigProvider)

    self.selectedSoundFontManager = SelectedSoundFontManager()
    self.activePresetManager = ActivePresetManager(soundFonts: soundFonts, favorites: favorites,
                                                   selectedSoundFontManager: selectedSoundFontManager,
                                                   settings: settings)
    self.activeTagManager = ActiveTagManager(tags: tags, settings: settings)

    super.init()

    createAudioComponents()
  }

  public func createAudioComponents() {
    if self.inApp {
      DispatchQueue.global(qos: .userInitiated).async {
        let sampler = Sampler(mode: .standalone, activePresetManager: self.activePresetManager, reverb: ReverbEffect(),
                              delay: DelayEffect(), chorus: ChorusEffect(), settings: self.settings)
        self.accessQueue.sync { self._sampler = sampler }
      }
    } else {
      self._sampler = Sampler(mode: .audioUnit, activePresetManager: self.activePresetManager, reverb: nil, delay: nil,
                              chorus: nil, settings: settings)
    }
  }

  /**
   Install the main view controller

   - parameter mvc: the main view controller to use
   */
  public func setMainViewController(_ mvc: T) {
    mainViewController = mvc

    let alertManager = AlertManager(presenter: mvc)
    accessQueue.sync { _alertManager = alertManager }

    for obj in mvc.children {
      processChildController(obj)
    }

    validate()

    establishConnections()
  }

  /**
   Invoke `establishConnections` on each tracked view controller.
   */
  public func establishConnections() {
    fontsTableViewController.establishConnections(self)
    presetsTableViewController.establishConnections(self)
    tagsTableViewController.establishConnections(self)
    soundFontsViewController.establishConnections(self)
    favoritesController.establishConnections(self)
    infoBarController.establishConnections(self)
    keyboardController?.establishConnections(self)
    guideController.establishConnections(self)
    soundFontsControlsController.establishConnections(self)
    effectsController?.establishConnections(self)
    mainViewController.establishConnections(self)
  }
}

extension Components {

  private func processChildController(_ obj: UIViewController) {
    switch obj {
    case let vc as SoundFontsControlsController:
      soundFontsControlsController = vc
      for obj in vc.children {
        processChildController(obj)
      }

    case let vc as SoundFontsViewController:
      soundFontsViewController = vc
      for obj in vc.children {
        processChildController(obj)
      }

    case let vc as KeyboardController: keyboardController = vc
    case let vc as GuideViewController: guideController = vc
    case let vc as FavoritesViewController: favoritesController = vc
    case let vc as InfoBarController: infoBarController = vc
    case let vc as FontsTableViewController: fontsTableViewController = vc
    case let vc as PresetsTableViewController: presetsTableViewController = vc
    case let vc as TagsTableViewController: tagsTableViewController = vc
    case let vc as EffectsController: effectsController = vc

    default: assertionFailure("unknown child UIViewController")
    }
  }

  private func validate() {
    precondition(mainViewController != nil, "nil MainViewController")
    precondition(soundFontsControlsController != nil, "nil SoundFontsControlsController")
    precondition(infoBarController != nil, "nil InfoBarController")
    precondition(soundFontsViewController != nil, "nil SoundFontsViewController")
    precondition(favoritesController != nil, "nil FavoritesViewController")
    precondition(guideController != nil, "nil GuidesController")
    precondition(effectsController != nil, "nil EffectsController")
    precondition(fontsTableViewController != nil, "nil FontsTableViewController")
    precondition(presetsTableViewController != nil, "nil PresetsTableViewController")
  }

  private func oneTimeSet<T>(_ oldValue: T?) {
    if oldValue != nil {
      preconditionFailure("expected nil value")
    }
  }
}

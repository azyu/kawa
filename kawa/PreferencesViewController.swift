import Cocoa

class PreferencesViewController: NSViewController {
  @IBOutlet weak var showNotificationCheckbox: NSButton!
  @IBOutlet weak var modifierToggleCheckbox: NSButton!
  @IBOutlet weak var shiftSpaceToggleCheckbox: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    showNotificationCheckbox.state = PermanentStorage.showsNotification.stateValue
    modifierToggleCheckbox.state = PermanentStorage.modifierToggleEnabled.stateValue
    shiftSpaceToggleCheckbox.state = PermanentStorage.shiftSpaceToggleEnabled.stateValue
  }

  @IBAction func quitApp(_ sender: NSButton) {
    NSApplication.shared.terminate(nil)
  }

  @IBAction func showNotification(_ sender: NSButton) {
    PermanentStorage.showsNotification = sender.state.boolValue
    if sender.state.boolValue {
      NotificationManager.requestAuthorizationIfNeeded()
    }
  }

  @IBAction func toggleModifierToggle(_ sender: NSButton) {
    PermanentStorage.modifierToggleEnabled = sender.state.boolValue
    if sender.state.boolValue {
      ModifierToggleMonitor.shared.start()
    } else if !PermanentStorage.shiftSpaceToggleEnabled {
      ModifierToggleMonitor.shared.stop()
    }
  }

  @IBAction func toggleShiftSpaceToggle(_ sender: NSButton) {
    PermanentStorage.shiftSpaceToggleEnabled = sender.state.boolValue
    if sender.state.boolValue {
      ModifierToggleMonitor.shared.start()
    } else {
      ModifierToggleMonitor.shared.shiftSpaceMonitor.stop()
      if !PermanentStorage.modifierToggleEnabled {
        ModifierToggleMonitor.shared.stop()
      }
    }
  }
}

private extension Bool {
  var stateValue: NSControl.StateValue {
    return self ? .on : .off;
  }
}

private extension NSControl.StateValue {
  var boolValue: Bool {
    return self == .on;
  }
}

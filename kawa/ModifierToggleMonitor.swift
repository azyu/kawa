import Carbon
import Cocoa

class ModifierToggleMonitor {
  static let shared = ModifierToggleMonitor()

  private let koreanSourceID = "com.apple.inputmethod.Korean.2SetKorean"
  private let japaneseSourceID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
  private let englishSourceIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]

  private let leftOptionKeyCode: UInt16 = 0x3A
  private let leftShiftKeyCode: UInt16 = 0x38
  private let spaceKeyCode: UInt16 = 0x31

  private var pressedModifiers: Set<UInt16> = []
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var spaceConsumeTap: CFMachPort?
  private var spaceConsumeRunLoopSource: CFRunLoopSource?
  private var localKeyMonitor: Any?

  // Pure CGEvent state for Shift+Space (replaces ShiftSpaceHIDMonitor)
  private let deviceLeftShiftMask: UInt64 = 0x00000002
  private var isLeftShiftHeldForSpace = false
  private var consumedSpaceKeyDown = false

  func start() {
    guard eventTap == nil else { return }

    if !CGPreflightListenEventAccess() {
      CGRequestListenEventAccess()
    }

    let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: eventMask,
      callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
        let monitor = Unmanaged<ModifierToggleMonitor>.fromOpaque(refcon!).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
          }
          monitor.pressedModifiers.removeAll()
          return Unmanaged.passUnretained(event)
        }

        monitor.handleFlagsChanged(event)
        return Unmanaged.passUnretained(event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      return
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    ensureShiftSpaceState()
  }

  /// Start/stop space consume tap and local key monitor
  /// based on the current shiftSpaceToggleEnabled preference.
  /// Safe to call repeatedly — each sub-component guards against double-start.
  func ensureShiftSpaceState() {
    let enabled = PermanentStorage.shiftSpaceToggleEnabled
    if enabled {
      startSpaceConsumeTap()
      startLocalKeyMonitor()
    } else {
      stopLocalKeyMonitor()
      stopSpaceConsumeTap()
    }
  }

  func stop() {
    stopLocalKeyMonitor()
    stopSpaceConsumeTap()

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      runLoopSource = nil
    }
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      eventTap = nil
    }
    pressedModifiers.removeAll()
  }

  // MARK: - Space Consume Tap (Accessibility, prevents space character)

  private func startSpaceConsumeTap() {
    guard PermanentStorage.shiftSpaceToggleEnabled else { return }
    guard spaceConsumeTap == nil else { return }

    // Request Accessibility permission (shows system dialog if not granted)
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else { return }

    let eventMask = CGEventMask(
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
    )

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
        let monitor = Unmanaged<ModifierToggleMonitor>.fromOpaque(refcon!).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          if let tap = monitor.spaceConsumeTap {
            CGEvent.tapEnable(tap: tap, enable: true)
          }
          return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
          monitor.handleSpaceTapFlagsChanged(event)
          return Unmanaged.passUnretained(event)
        case .keyDown:
          return monitor.handleKeyDown(event)
        case .keyUp:
          return monitor.handleKeyUp(event)
        default:
          return Unmanaged.passUnretained(event)
        }
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      return
    }

    spaceConsumeTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    spaceConsumeRunLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func stopSpaceConsumeTap() {
    if let source = spaceConsumeRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      spaceConsumeRunLoopSource = nil
    }
    if let tap = spaceConsumeTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      spaceConsumeTap = nil
    }
    isLeftShiftHeldForSpace = false
    consumedSpaceKeyDown = false
  }

  // MARK: - Space Consume Tap event handlers

  /// Track Left Shift state from flagsChanged events in the space consume tap.
  /// Uses NX_DEVICELSHIFTKEYMASK (0x02) to distinguish Left from Right Shift.
  private func handleSpaceTapFlagsChanged(_ event: CGEvent) {
    let rawFlags = event.flags.rawValue
    let hasLeftShift = (rawFlags & deviceLeftShiftMask) != 0
    isLeftShiftHeldForSpace = hasLeftShift
  }

  /// Returns nil to consume the event, or the event to pass through.
  private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == spaceKeyCode else { return Unmanaged.passUnretained(event) }
    guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return Unmanaged.passUnretained(event) }
    guard isLeftShiftHeldForSpace else { return Unmanaged.passUnretained(event) }
    let unwanted: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
    guard event.flags.isDisjoint(with: unwanted) else { return Unmanaged.passUnretained(event) }
    let toggled = toggleKoreanEnglish()
    if toggled {
      consumedSpaceKeyDown = true
      return nil
    }
    return Unmanaged.passUnretained(event)
  }

  /// Consume keyUp for Space if the corresponding keyDown was consumed.
  private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == spaceKeyCode else { return Unmanaged.passUnretained(event) }
    guard consumedSpaceKeyDown else { return Unmanaged.passUnretained(event) }
    consumedSpaceKeyDown = false
    return nil
  }

  // MARK: - Local Key Monitor (beep suppression fallback)

  private func startLocalKeyMonitor() {
    guard localKeyMonitor == nil else { return }
    guard PermanentStorage.shiftSpaceToggleEnabled else { return }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }
      if self.shouldConsumeAsShiftSpace(event) {
        return nil
      }
      return event
    }
  }

  private func stopLocalKeyMonitor() {
    if let monitor = localKeyMonitor {
      NSEvent.removeMonitor(monitor)
      localKeyMonitor = nil
    }
  }

  // MARK: - CGEvent flagsChanged (Left Option + Left Shift toggle)

  private func handleFlagsChanged(_ event: CGEvent) {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    guard PermanentStorage.modifierToggleEnabled else { return }

    guard keyCode == leftOptionKeyCode || keyCode == leftShiftKeyCode else {
      pressedModifiers.removeAll()
      return
    }

    let isOptionPressed = flags.contains(.maskAlternate)
    let isShiftPressed = flags.contains(.maskShift)

    if keyCode == leftOptionKeyCode {
      if isOptionPressed {
        pressedModifiers.insert(keyCode)
      } else {
        pressedModifiers.remove(keyCode)
      }
    } else if keyCode == leftShiftKeyCode {
      if isShiftPressed {
        pressedModifiers.insert(keyCode)
      } else {
        pressedModifiers.remove(keyCode)
      }
    }

    let unwantedFlags: CGEventFlags = [.maskCommand, .maskControl]
    if pressedModifiers == [leftOptionKeyCode, leftShiftKeyCode] && flags.isDisjoint(with: unwantedFlags) {
      toggle()
      pressedModifiers.removeAll()
    }
  }

  // MARK: - Shift+Space helpers

  private func shouldConsumeAsShiftSpace(_ event: NSEvent) -> Bool {
    guard PermanentStorage.shiftSpaceToggleEnabled else { return false }
    guard event.keyCode == spaceKeyCode else { return false }
    guard !event.isARepeat else { return false }
    guard isLeftShiftHeldForSpace else { return false }
    let unwanted: NSEvent.ModifierFlags = [.command, .control, .option]
    guard event.modifierFlags.isDisjoint(with: unwanted) else { return false }
    return toggleKoreanEnglish()
  }

  // MARK: - Input source switching

  /// Returns true if an input source switch actually occurred.
  @discardableResult
  private func toggleKoreanEnglish() -> Bool {
    guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
    let currentID = currentSource.id

    if currentID == koreanSourceID {
      let sources = InputSource.sources
      guard let english = sources.first(where: { self.englishSourceIDs.contains($0.id) }) else { return false }
      english.select()
      return true
    } else if englishSourceIDs.contains(currentID) {
      let sources = InputSource.sources
      if let target = sources.first(where: { $0.id == koreanSourceID }) {
        target.select()
        return true
      }
    }
    return false
  }

  private func toggle() {
    guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
    let currentID = currentSource.id

    let targetID: String
    if currentID == koreanSourceID {
      targetID = japaneseSourceID
    } else if currentID == japaneseSourceID {
      targetID = koreanSourceID
    } else {
      return
    }

    let sources = InputSource.sources
    if let target = sources.first(where: { $0.id == targetID }) {
      target.select()
    }
  }
}

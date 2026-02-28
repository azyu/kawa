import Carbon
import Cocoa

class ModifierToggleMonitor {
  static let shared = ModifierToggleMonitor()

  private let koreanSourceID = "com.apple.inputmethod.Korean.2SetKorean"
  private let japaneseSourceID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

  private let leftOptionKeyCode: UInt16 = 0x3A
  private let leftShiftKeyCode: UInt16 = 0x38

  private var pressedModifiers: Set<UInt16> = []
  private var eventTap: CFMachPort?

  func start() {
    let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: eventMask,
      callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
        let monitor = Unmanaged<ModifierToggleMonitor>.fromOpaque(refcon!).takeUnretainedValue()
        monitor.handleFlagsChanged(event)
        return Unmanaged.passUnretained(event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      NSLog("ModifierToggleMonitor: Failed to create event tap. Input Monitoring permission may be required.")
      return
    }

    eventTap = tap
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func stop() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      eventTap = nil
    }
  }

  private func handleFlagsChanged(_ event: CGEvent) {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    guard keyCode == leftOptionKeyCode || keyCode == leftShiftKeyCode else {
      pressedModifiers.removeAll()
      return
    }

    let flags = event.flags

    // Check if the key was pressed or released by examining relevant flags
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

    // Trigger only when exactly Left Option + Left Shift are pressed, with no other modifiers
    let unwantedFlags: CGEventFlags = [.maskCommand, .maskControl]
    if pressedModifiers == [leftOptionKeyCode, leftShiftKeyCode] && flags.isDisjoint(with: unwantedFlags) {
      toggle()
      pressedModifiers.removeAll()
    }
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

    // Find and select the target input source
    let sources = InputSource.sources
    if let target = sources.first(where: { $0.id == targetID }) {
      target.select()
    }
  }
}

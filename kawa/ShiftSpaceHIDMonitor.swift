import Cocoa
import IOKit.hid

final class ShiftSpaceHIDMonitor {
  private var manager: IOHIDManager?
  private(set) var isLeftShiftDown = false
  private var spaceDown = false
  private var leftCommandDown = false
  private var leftControlDown = false
  private var leftOptionDown = false
  private var rightCommandDown = false
  private var rightControlDown = false
  private var rightOptionDown = false

  /// Per-device set of currently pressed key usages (for array-type HID elements)
  private var devicePressedKeys: [IOHIDDevice: Set<Int>] = [:]

  var onTrigger: (() -> Void)?

  func start() {
    guard manager == nil else { return }

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching = [
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary
    IOHIDManagerSetDeviceMatching(mgr, matching)

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
      let monitor = Unmanaged<ShiftSpaceHIDMonitor>.fromOpaque(context!).takeUnretainedValue()
      monitor.handle(value: value)
    }, context)

    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else { return }

    manager = mgr
  }

  func stop() {
    guard let mgr = manager else { return }
    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    manager = nil
    resetState()
  }

  private func resetState() {
    isLeftShiftDown = false
    spaceDown = false
    leftCommandDown = false
    leftControlDown = false
    leftOptionDown = false
    rightCommandDown = false
    rightControlDown = false
    rightOptionDown = false
    devicePressedKeys.removeAll()
  }

  private func handle(value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intVal = IOHIDValueGetIntegerValue(value)
    let device = IOHIDElementGetDevice(element)

    guard usagePage == kHIDPage_KeyboardOrKeypad else { return }

    // Dedicated modifier elements (usage 0xE0–0xE7): val=1 pressed, val=0 released
    if usage >= 0xE0 && usage <= 0xE7 {
      if intVal != 0 {
        handleKeyDown(Int(usage), device: device)
      } else {
        handleKeyUp(Int(usage), device: device)
      }
      return
    }

    // Array elements (Apple keyboards): usage=0xFFFFFFFF, intVal = usage of pressed key
    if usage == 0xFFFFFFFF {
      let keyUsage = Int(intVal)
      let prevKeys = devicePressedKeys[device] ?? []

      if keyUsage > 1 { // skip 0 (no key) and 1 (ErrorRollOver)
        if !prevKeys.contains(keyUsage) {
          var updated = prevKeys
          updated.insert(keyUsage)
          devicePressedKeys[device] = updated
          handleKeyDown(keyUsage, device: device)
        }
      } else if keyUsage == 0 {
        devicePressedKeys[device] = []
        for k in prevKeys {
          handleKeyUp(k, device: device)
        }
      }
      return
    }

    // Standard selector elements
    if usage == 0x01 { return } // ErrorRollOver
    if intVal != 0 {
      handleKeyDown(Int(usage), device: device)
    } else {
      handleKeyUp(Int(usage), device: device)
    }
  }

  private func handleKeyDown(_ keyUsage: Int, device: IOHIDDevice) {
    switch keyUsage {
    case kHIDUsage_KeyboardLeftShift:
      isLeftShiftDown = true
    case kHIDUsage_KeyboardLeftControl:
      leftControlDown = true
    case kHIDUsage_KeyboardLeftAlt:
      leftOptionDown = true
    case kHIDUsage_KeyboardLeftGUI:
      leftCommandDown = true
    case kHIDUsage_KeyboardRightControl:
      rightControlDown = true
    case kHIDUsage_KeyboardRightAlt:
      rightOptionDown = true
    case kHIDUsage_KeyboardRightGUI:
      rightCommandDown = true
    case kHIDUsage_KeyboardSpacebar:
      if !spaceDown {
        spaceDown = true
        if isLeftShiftDown && !anyModifierDown {
          onTrigger?()
        }
      }
    default:
      break
    }
  }

  private func handleKeyUp(_ keyUsage: Int, device: IOHIDDevice) {
    switch keyUsage {
    case kHIDUsage_KeyboardLeftShift:
      isLeftShiftDown = false
    case kHIDUsage_KeyboardLeftControl:
      leftControlDown = false
    case kHIDUsage_KeyboardLeftAlt:
      leftOptionDown = false
    case kHIDUsage_KeyboardLeftGUI:
      leftCommandDown = false
    case kHIDUsage_KeyboardRightControl:
      rightControlDown = false
    case kHIDUsage_KeyboardRightAlt:
      rightOptionDown = false
    case kHIDUsage_KeyboardRightGUI:
      rightCommandDown = false
    case kHIDUsage_KeyboardSpacebar:
      spaceDown = false
    default:
      break
    }
  }

  private var anyModifierDown: Bool {
    leftCommandDown || leftControlDown || leftOptionDown
      || rightCommandDown || rightControlDown || rightOptionDown
  }
}

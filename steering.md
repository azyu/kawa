# Steering — 문제 해결 시도 기록

> **이 파일을 반드시 읽고 나서 문제 해결을 시도할 것.** 같은 접근 반복 금지.

## Shift+Space 한/영 전환 시 Space 문자 누출

| # | 접근 | 구현 | 결과 | 실패 원인 |
|---|------|------|------|-----------|
| 1 | HID latch + CGEvent tap keyDown 소비 | `ShiftSpaceHIDMonitor`(IOHIDManager)가 Left Shift 상태 추적. `spaceConsumeTap`(CGEvent, keyDown만)이 latch 확인 후 Space keyDown을 nil 반환 | **실패** — Space 여전히 누출 | (a) **keyUp 미소비**: 이벤트 마스크가 keyDown만 포함. keyDown nil 반환해도 keyUp 통과 → 한글 IME가 keyUp에서 문자 삽입. (b) **HID↔CGEvent 타이밍 레이스**: IOHIDManager와 CGEvent tap이 같은 run loop의 서로 다른 source — 디스패치 순서 비결정적 → HID 상태가 CGEvent tap 시점에 아직 반영 안 될 수 있음 |
| 2 | Pure CGEvent tap (HID 의존성 완전 제거) | 단일 `spaceConsumeTap`에서 `flagsChanged`+`keyDown`+`keyUp` 모두 처리. `flagsChanged`에서 `NX_DEVICELSHIFTKEYMASK`(0x02)로 Left Shift 추적. keyDown 소비 시 `consumedSpaceKeyDown` 플래그 → keyUp도 소비. `ShiftSpaceHIDMonitor` 삭제 | **성공** — 권한 재부여(Input Monitoring + Accessibility OFF→ON) 후 정상 동작 | 초기 "미동작"은 코드 문제가 아니라 **TCC 권한 재평가** 이슈였음. 재서명된 바이너리에 대해 macOS가 기존 권한을 신뢰하지 않음 → 권한 토글 필요 |

## macOS IME API 변화 타임라인

| macOS | 변화 |
|-------|------|
| **13 Ventura** | CGEvent tap 간헐적 이벤트 수신 중단 버그(FB12113281). 샌드박스 앱 `TISSelectInputSource` 차단 (`com.apple.tsm.portname` deny) |
| **14 Sonoma** | TCC 권한 검증 강화 — 코드 서명 기반 재평가. `TISSelectInputSource` CJKV 불안정 악화. skhd 등 기존 앱 Accessibility 재부여 필요 |
| **15 Sequoia** | CGEvent tap + 코드 서명 "silent disable" — 재서명 후 Launch Services 실행 시 tap 설치되지만 콜백 미수신. Terminal 직접 실행은 정상. Input Monitoring/Accessibility TCC 정책 더 엄격 |

**결론**: macOS 15 기준 빌드 타겟으로 결정. `TISSelectInputSource` Carbon API 자체는 deprecated 아님. TCC 권한 재평가가 주요 변수이며, 코드 재서명 후 권한 재부여 필요.

## 참고 자료

- **keyUp 소비 필요성**: alt-tab-macos #633, #2914 — keyUp 미소비가 키 누출 원인
- **`NX_DEVICELSHIFTKEYMASK`**: `0x00000002`, macOS SDK `IOLLEvent.h`. `CGEventFlags.rawValue`에 device-specific bit 포함
- **Karabiner-Elements**: pure CGEvent tap 접근으로 키 소비 구현 (HID는 감지 전용, 소비는 CGEvent)
- **CGEvent tap silent disable**: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/
- **Karabiner CJKV 이슈**: https://github.com/tekezo/Karabiner-Elements/issues/1602

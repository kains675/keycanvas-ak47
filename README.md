# KeyCanvas

AK47 맥에서 쓰려고 만들었어요.

<img src="Artwork/keycanvas-mark.svg" alt="KeyCanvas 앱 마크" width="160">

KeyCanvas는 **ARCHON AK47 non-PRO**를 위한 독립 오픈소스 macOS 앱입니다.
현재 확인하는 USB 장치는 `VID 0x0C45`, `PID 0x800A`입니다. AK47 PRO나
다른 하드웨어 revision과의 호환성은 보장하지 않습니다.

제조사 공식 앱이 아니며, 제조사 또는 상표권자와 제휴·후원·보증 관계가
없습니다. 제품명은 호환 대상을 설명하기 위해서만 사용합니다.

> **비공식 개인 개발 프로젝트 · 무보증**
>
> KeyCanvas는 개인이 독립적으로 개발하는 실험적 소프트웨어이며 제조사의
> 보증이나 지원 대상이 아닙니다. 소프트웨어는 [MIT License](LICENSE)에 따라
> **있는 그대로(AS IS)** 제공되고, 상품성·특정 목적 적합성 등을 보증하지
> 않습니다. 장치 작업에는 저장된 설정이 바뀌거나 예상과 다른 결과가 생길
> 위험이 있으므로 실행 여부와 결과를 사용자가 직접 판단해야 합니다. 법이
> 허용하는 범위에서 저작권자와 기여자는 사용 또는 사용 불능으로 발생하는
> 청구·손해·기타 책임을 부담하지 않습니다. 적용되는 법률이 보장하는 권리를
> 이 안내가 제한한다는 뜻은 아닙니다.

> **현재는 로컬 편집과 정확히 제한된 유선 장치 작업을 제공하는 프로토타입입니다.**
> 편집값은 자동으로 전송되지 않습니다. 정확한 대상 장치에서 작업별 확인을 거친
> 경우에만 시계 동기화, 현재 선택한 내장 조명 모드 하나, 또는 완성된 84키 RGB
> 표를 한 번 적용할 수 있습니다. 현재 RGB를 읽는 별도의 키별 F5 단발 질의도
> 매번 확인 후에만 실행됩니다.

## 지금 할 수 있는 것

- macOS용 독립 SwiftUI 인터페이스
- 한국어·영어 전환
- Dashboard, Keymap, Lighting, Macros, Display, Settings 화면
- 84키 Base/Fn 키맵 초안 편집
- AK47 non-PRO에서 확인된 19개 내장 조명 모드의 로컬 선택과 84키 애니메이션
  개념 미리보기
- 실제 84키 위치와 RGB 슬롯을 사용하는 키별 색상 페인터
- 유효성을 검사하는 매크로 초안
- 240×135 디스플레이 구성 미리보기
- Windows의 `Archon AK47 Driver Files` 백업에서 로컬 프로필과 LCD 레이어 가져오기
- 설정값 로컬 저장과 검증된 JSON 가져오기·내보내기
- 연결된 AK47 HID 컬렉션의 읽기 전용 메타데이터 확인
- 사용자가 직접 누를 때만 실행되는 feature/output `GetReport` 진단
- 사용자가 별도 확인한 뒤 한 번만 실행하는 현재 키별 RGB 조회
- 사용자가 작업별 확인을 거친 뒤 실행하는 시계 동기화
- 0–19번 중 현재 선택한 내장 모드 하나와 그 조절값의 단발 적용
- 누락 없이 완성된 84키 RGB 표와 밝기의 단발 적용
- USB `bcdDevice` 버전 표시
- 사람용·JSON 형식을 지원하는 CLI 장치 검사기
- 정제된 로컬 trace를 비교하는 오프라인 분석기

프로필은 다음 위치에 저장됩니다.

```text
~/Library/Application Support/KeyCanvas
```

프로필 저장·가져오기·내보내기는 Mac의 파일만 변경합니다.

조명 화면의 `Static`부터 `Shuttle`까지 19개 이름과 순서는 AK47 non-PRO Windows
앱의 1033·1042 언어 리소스 철자 그대로 표시합니다. 밝기·속도·방향·RGB 조절 가능
여부도 같은 Windows 앱에서 확인한 값입니다. 미리보기는 Keymap과
같은 672×226 캔버스, 실제 84키 형상과 확인된 `lightIndex` 대응을 공유하고
`TimelineView`로 계속 움직입니다. 반응형으로 분류한 2·3·13·14·15번 모드는 키를
클릭하거나 자동으로 만든 가상 입력으로 반응을 볼 수 있습니다. 이 입력은 화면
안에서만 처리되며 HID 명령을 보내지 않습니다.

효과의 정확한 시간·공간 공식은 펌웨어에서 읽어 온 것이 아니므로 애니메이션은
KeyCanvas가 독자적으로 만든 근사 시안이며 실제 펌웨어 동작을 그대로 재현한다고
주장하지 않습니다. 조명을 끄는 상태는 별도 효과로 만들지 않고 프로필의
`enabled` 값으로 저장합니다. 미리보기·키 클릭·가상 입력은 장치와 통신하지
않으며, 편집값은 조명 화면의 해당 적용 버튼을 누르고 별도 확인을 마친 경우에만
한 번 전송됩니다.

Windows 백업 가져오기는 사용자가 직접 선택한 폴더의 SQLite DB를 읽기 전용으로
제한 조회합니다. 함께 저장된 PNG 프레임은 크기·개수·경로를 검사한 뒤 원본
레이어의 픽셀 크기와 프레임 지연을 보존한 GIF로 앱 전용 폴더에 복사합니다.
키보드 화면 캔버스는 240×135로 유지되어 미리보기에서 비율에 맞춰 표시됩니다.
이 기능은 Windows 프로그램을 실행하거나 네트워크·키보드에 접근하지 않으며,
가져온 값은 장치의 현재 상태가 아니라 Windows 앱이 마지막으로 저장한 로컬
상태입니다. 일관된 백업을 위해 Windows 설정 앱을 완전히 종료한 뒤 폴더를
복사하세요. WAL·journal sidecar가 남은 활성 DB는 가져오기를 거부합니다.

Windows 백업에는 사용자 이미지, 컴퓨터 이름, 장치 식별자 또는 제3자 저작물이
포함될 수 있습니다. 원본 백업이나 `analysis/` 폴더를 저장소, Issue, PR 또는
Release에 올리지 마세요.

## 아직 할 수 없는 것

- 키맵, 매크로, LCD 이미지 또는 일반 장치 설정을 실제 키보드에 적용
- 시계, 선택한 내장 조명 하나, 완성된 84키 RGB 이외의 설정 변경 또는 임의
  `SetReport`와 output report 전송
- 현재 키맵·매크로·LCD 내용·일반 설정과 내장 모드·밝기·속도·방향 읽기
- 내장 모드 적용 전 상태의 정확한 백업·자동 복원·rollback
- 장치 인터페이스 점유
- 실시간 USB/HID 캡처, 공식 앱 후킹 또는 report 재생
- 펌웨어 읽기·추출·업데이트·플래시
- 무선, 2.4GHz 또는 Bluetooth 설정 지원 보장
- AK47 PRO 및 다른 하드웨어 revision 지원 보장

같은 제품명이라도 생산 시기에 따라 내부 하드웨어가 다를 수 있습니다.

## 지원 환경과 대상 장치

- 배포 앱: macOS 13 이상, Apple Silicon 및 Intel Mac
- 소스 빌드: macOS 13 이상, Swift 5.9 이상, Xcode 또는 Xcode Command Line Tools
- 외부 Swift 패키지 의존성 없음

장치 작업은 아래 항목이 **모두** 일치하는 한 가지 유선 장치에서만 활성화됩니다.

| 항목 | 정확한 대상 |
| --- | --- |
| 연결 | 유선 USB |
| USB VID:PID | `0x0C45:0x800A` |
| 제품 문자열 | `Archon AK47` |
| 장치 revision (`bcdDevice`) | `0x0115` |
| 명령용 HID 컬렉션 | usage page `0xFF13`, usage `0x0001`, 64바이트 Feature report |

앱은 장치 작업 전후에 이 값과 아래에 적은 네 HID 컬렉션의 전체 구성을 다시
검사합니다. **AK47 PRO, 다른 revision, 2.4GHz 및 Bluetooth 연결은 지원 대상으로
간주하지 않습니다.** 같은 제품명이라도 내부 하드웨어가 다를 수 있습니다.

## 설치

> 배포본도 제조사가 서명·공증한 공식 드라이버가 아닌 **공증되지 않은
> 실험판**입니다. 설치 자체로 키보드에 명령을 보내지는 않지만, 앱 안에서
> 작업별 확인을 마치고 적용하면 장치 상태가 바뀝니다. 내장 모드 조절값에는
> 정확한 사전 백업·자동 복원 경로가 없습니다. 출처와 SHA-256을 확인하고 위험을
> 이해한 경우에만 사용하세요. 소프트웨어는 무보증이며 책임 제한은
> [MIT License](LICENSE)와 적용 법률이 허용하는 범위에 따릅니다.

### 공증되지 않은 개발자 미리보기 DMG로 설치

Developer ID와 Apple 공증이 준비되기 전의 바이너리는 GitHub에서 **Pre-release**로만
배포합니다. 가장 보수적인 방법은 아래의 소스 빌드이며, Pre-release DMG는 출처와
체크섬을 직접 검증하고 공증되지 않은 앱의 위험을 이해한 경우에만 사용하세요.

1. [GitHub Releases](https://github.com/kains675/keycanvas-ak47/releases)에서
   `Pre-release`로 표시된 개발자 미리보기의 `.dmg`와 SHA-256 파일을 받습니다.
2. 다운로드한 DMG의 SHA-256이 Release에 게시된 값과 일치하는지 확인합니다.
3. DMG를 열고 `KeyCanvas.app`을 `Applications` 폴더로 드래그합니다.
4. 복사가 끝나면 DMG를 추출하고 `/Applications/KeyCanvas.app`을 실행합니다.

동반된 `.dmg.sha256` 파일을 같은 폴더에 받았다면 터미널에서도 확인할 수
있습니다. 결과가 `OK`가 아니면 DMG를 열지 마세요.

```sh
cd ~/Downloads
shasum -a 256 -c KeyCanvas-*.dmg.sha256
```

### APP 또는 ZIP으로 실행

ZIP 배포본은 먼저 압축을 풉니다. 나온 `KeyCanvas.app`을 `Applications`로
옮기는 것을 권장하지만, 신뢰하는 로컬 폴더에서 앱을 직접 실행해도 됩니다.
업데이트할 때는 앱을 완전히 종료한 뒤 기존 앱을 새 `KeyCanvas.app`으로
교체하세요. 앱을 실행 중인 채로 덮어쓰지 마세요.

### 첫 실행과 Gatekeeper

배포본에는 Developer ID 서명과 Apple 공증이 없으므로 macOS가 첫 실행을 막을
수 있습니다. 이는 정상적인 보안 경고입니다. 출처나 SHA-256을 확신할 수 없다면
경고를 우회하지 말고 앱을 삭제한 뒤 소스에서 빌드하세요.

Release 출처와 SHA-256을 직접 확인했고 위험을 수용한 경우에만 Finder에서
`KeyCanvas.app`을 Control-클릭(또는 오른쪽 클릭)하고 **열기 → 열기**를 선택할 수
있습니다. macOS가 계속 거부하거나 파일이 손상됐다고 표시하면 강제로 실행하지
말고 삭제하세요. `xattr`로 quarantine을 지우거나 Gatekeeper를 시스템 전체에서
끄는 방법은 안내하거나 권장하지 않습니다.

### 소스에서 실행하거나 앱 번들 만들기

```sh
git clone https://github.com/kains675/keycanvas-ak47.git
cd keycanvas-ak47
swift run keycanvas
```

설치 가능한 Universal 2 앱 번들과 ZIP을 직접 만들려면 다음을 실행합니다.

```sh
sh Scripts/build-app.sh
open dist/KeyCanvas.app
```

드래그앤드롭 DMG와 SHA-256 파일까지 만들려면 다음을 실행합니다. 이 명령은
기본적으로 앱과 ZIP도 새로 빌드합니다.

```sh
sh Scripts/build-dmg.sh
```

로컬 결과물은 기본적으로 ad-hoc 서명되고 공증되지 않습니다.

## 개발용 CLI

CLI 장치 검사기는 공개 IOHID 레지스트리 속성만 열거합니다.

```sh
swift run ak47-inspect
swift run ak47-inspect --json
```

CLI에 표시되는 report 크기는 IOHID 레지스트리의 메타데이터입니다. HID
report 자체를 읽는 동작은 아닙니다.

앱의 장치 검사기에는 두 가지 수동 진단이 있습니다. 직접 report 진단은 정확히
일치하는 vendor collection을 `kIOHIDOptionsTypeNone`으로 잠깐 열고 `GetReport`만
호출한 뒤 즉시 닫습니다. 이 경로는 `SetReport`, output 전송, selector 명령,
자동 재시도 또는 파일 저장을 하지 않습니다.

키별 RGB 조회와 세 가지 장치 적용은 서로 독립된 확인 창을 거치는 단발
동작입니다. 모두 유선 USB `0x0C45:0x800A`, 제품명 `Archon AK47`, `bcdDevice
0x0115`와 아래 네 HID 컬렉션이 모두 정확히 일치할 때만 실행됩니다.

| usage page / usage | input | output | feature |
| --- | ---: | ---: | ---: |
| `0x0001 / 0x0006` | 8 | 1 | 0 |
| `0x000C / 0x0001` | 16 | 1 | 1 |
| `0xFF13 / 0x0001` | 64 | 64 | 64 |
| `0xFF68 / 0x0061` | 64 | 4096 | 0 |

키별 F5 조회는 질의 응답과 64바이트 보고서 9개를 받아 84키를 모두 파싱한 뒤
정상 종료합니다. 결과는 메모리에만 유지됩니다. 이 경로는 내장 모드 ID,
밝기·속도·방향, 키맵, LCD 또는 매크로를 읽는 일반 상태 조회가 아닙니다.

확인 후 실행할 수 있는 장치 적용 범위는 다음 세 가지뿐입니다.

- 현재 Mac의 로컬 날짜와 시각을 첫 번째 화면 시계 슬롯에 동기화
- `LED Off`를 포함한 0–19번 중 현재 선택한 내장 조명 모드 하나와 색상·밝기·
  속도·방향 적용
- 검증된 84개 `lightIndex`가 정확히 한 번씩 들어 있는 전체 키별 RGB 표와 밝기
  적용

각 작업은 종류가 일치하는 확인 기록이 있어야 시작됩니다. 유선 FF13 Feature
컬렉션만 비독점으로 열며, 세 적용 작업은 각 명령과 필요한 ACK 사이에 35ms
간격을 둡니다.
비동기 Feature 작업은 각각 360ms로 제한되고, ACK가 필요한 단계는 64바이트
응답의 byte 3이 성공값인지 검사합니다. 실패하면 즉시 중단하며 자동 재시도,
output report, LCD·키맵·매크로 전송, 원시 report 로그, 펌웨어·부트로더 작업은
없습니다. 세 적용 작업은 종료 뒤에도 동일한 네 컬렉션이 남아 있는지 다시
확인합니다.

ACK는 명령 수신을 뜻할 뿐 화면이나 조명 결과를 일반적으로 readback해 검증하는
기능은 아닙니다. 특히 내장 모드·밝기·속도·방향의 현재값을 읽거나 적용 전 상태로
정확히 되돌리는 경로는 없습니다. 84키 RGB만 별도의 F5 질의로 다시 읽을 수
있습니다. 따라서 세 적용 기능은 여전히 실험적이며 작업 전 현재 상태를 직접
확인해야 합니다.

세 적용 경로는 기본 테스트에서는 건너뛰며 작업별 확인 문구가 있을 때만
실행됩니다. 2026-08-09 정확히 식별된 유선 장치에서 수정된 시계 동기화, `Static`(1),
`Launch`(14)를 각각 한 번 적용했고 필요한 ACK와 종료 뒤 네 컬렉션 확인을
통과했습니다. 이어 밝기 3의 완성된 84키 3색 표도 한 번 적용했습니다. F5로 다시
읽은 결과는 모든 키의 색 배치를 유지했지만 원본 RGB보다 약 65%로 축소된 세
색이었습니다. 따라서 F5는 저장 원본을 그대로 돌려주는 백업 경로라기보다 현재
밝기가 반영된 출력 버퍼일 가능성이 높으며, 정확한 원본 복원을 보장하지 않습니다.

2026-08-09 첫 실기에서는 84키의 RGB 값이 모두 `0, 0, 0`이었습니다. 사용자가
키보드를 14번 모드로 바꿨다고 별도로 알려준 뒤 두 번째로 한 번 조회하자 84키가
모두 0이 아닌 값으로 바뀌었고 서로 다른 색 24개가 관찰됐습니다. Windows 쪽 이름
대응에서 14번은 `Launch`이며 KeyCanvas도 Windows 리소스 이름을 그대로 표시합니다. 이 결과는
한 시점의 RGB 스냅샷으로, 응답 자체에는 모드 ID가 없고 효과의 정확한 움직임
공식도 담겨 있지 않습니다. 따라서 이 응답이 현재 조명 상태에 따라 변하는 키별
RGB 버퍼라는 점은 확인했지만 방향·밝기·속도나 시간에 따른 움직임을 이 한 번의
조회만으로 확정할 수는 없습니다. 모든 실기 단계 뒤 장치는 같은 네 컬렉션으로
계속 열거됐고 연결 해제는 관찰되지 않았습니다. 실제 키보드의 시계 표시와 각
효과의 육안 결과는 별도로 확인해야 합니다.

현재 실기에서 요청 명령 없이 feature report를 직접 읽으면 64바이트의 `00`만
반환됐고, 4096바이트 LCD output report 읽기는 USB STALL로 거부됐습니다. 즉
이 단순 읽기 경로만으로는 키보드 설정이나 저장된 LCD 이미지를 백업할 수
없습니다.

## 다음 단계: 오프라인 trace 비교

실제 설정 명령을 추측해서 키보드에 보내지 않고, 한 번에 설정 하나만 바꾼
두 개의 **정제된 로컬 JSON trace**를 비교하는 단계입니다.

```sh
swift run keycanvas-trace summary sanitized-trace.json
swift run keycanvas-trace diff before.json after.json
swift run keycanvas-trace diff before.json after.json --json
```

이 분석기는 전달받은 파일을 오프라인에서 읽을 뿐 장치나 공식 앱을 열거나,
후킹·캡처·복호화·재생·전송하지 않습니다. 분석 결과는 검증되지 않은 관찰과
가설일 수 있으며 곧바로 하드웨어 명령으로 사용하면 안 됩니다.

모든 trace에는 `provenance` object가 필요합니다. `origin`은 `synthetic` 또는
`authorized-private-observation`이어야 하며 `authorizedUse`,
`identifiersRemoved`, `absoluteTimestampsRemoved`, `firmwareTrafficExcluded`는
모두 `true`여야 합니다. 이는 제출자의 확인을 구조화한 것이며 실제 권리나
정제 상태를 자동으로 증명하지는 않습니다.

`offsetMicros`가 하나라도 있으면 처음 존재하는 값은 `0`이어야 하고 이후 값은
감소할 수 없으며 최대 1시간(`3,600,000,000`µs)입니다. 사람용·JSON 출력 모두
입력 label과 개별·최초·최종 timestamp를 표시하지 않습니다. 비교 결과에는
payload 값이 아니라 달라진 byte offset만 표시됩니다.

공개 trace Core는 decode와 분석만 제공하고 trace 문서를 만드는 public encoder는
제공하지 않습니다. 실시간 캡처, 장치 I/O 및 report 재생 API도 없습니다.

입력 형식과 제한은 [오프라인 trace 형식](TRACE_FORMAT.md)에 정리되어 있습니다.

원본 캡처에는 실제 키 입력, 매크로, serial/location ID, 경로, 토큰, 화면
데이터나 펌웨어 조각이 포함될 수 있습니다. 원본 캡처는 저장소, Issue/PR,
Actions log/artifact 또는 Release에 올리지 마세요. 공개 테스트에는 프로젝트가
직접 작성한 최소 합성 데이터만 사용합니다.

저장소의 tracked JSON은 기본적으로 경계 검사에서 거부됩니다. 꼭 필요한
프로젝트 원본 JSON은 정확한 경로를 검사 스크립트에 명시적으로 예외 처리하고
provenance 검토를 받은 경우에만 허용할 수 있습니다.

## 빌드와 테스트

```sh
swift build
swift test
sh Scripts/check-readonly-api.sh
sh .github/scripts/repository-scan.sh
```

GitHub Actions에서도 Swift 빌드·테스트와 저장소 경계 검사를 실행합니다.

## 앱 번들 빌드 옵션

기본 빌드는 Apple Silicon과 Intel 코드를 함께 담은 Universal 2 앱, ZIP과
각 ZIP의 SHA-256 파일을 만듭니다.

```sh
sh Scripts/build-app.sh
```

결과물은 `dist/`에 생성되며 Git에는 포함되지 않습니다.

현재 Mac의 아키텍처만 빌드하려면 다음과 같이 실행합니다.

```sh
KEYCANVAS_UNIVERSAL=0 sh Scripts/build-app.sh
```

DMG는 `KeyCanvas.app`과 `/Applications` 바로가기만 담은 드래그앤드롭 이미지이며
별도의 installer package가 아닙니다. DMG와 SHA-256 파일은 다음 명령으로
만듭니다.

```sh
sh Scripts/build-dmg.sh
```

Developer ID 인증서가 있는 배포 관리자는 `KEYCANVAS_CODESIGN_IDENTITY`를 지정할
수 있지만 notarization은 별도 단계입니다. 인증서를 지정하지 않은 로컬 빌드는
ad-hoc 서명 상태입니다.

## 삭제

1. KeyCanvas를 완전히 종료합니다.
2. `/Applications/KeyCanvas.app` 또는 직접 실행하던 `KeyCanvas.app`을 휴지통으로
   옮깁니다.
3. 로컬 프로필과 가져온 디스플레이 자산까지 지우려면 Finder에서 **이동 → 폴더로
   이동**을 열고 `~/Library/Application Support`로 이동한 뒤 그 안의
   `KeyCanvas` 폴더를 휴지통으로 옮깁니다. 휴지통을 비우면 복구하기 어려우므로
   필요한 프로필을 먼저 내보내세요.
4. 앱 환경설정까지 초기화하려면, 앱을 종료한 상태에서 배포 앱의 UserDefaults
   도메인 `dev.keycanvas.app`을 삭제할 수 있습니다.

```sh
defaults delete dev.keycanvas.app
```

현재 배포 앱은 시스템 확장, 커널 확장 또는 권한 있는 helper를 설치하지 않습니다.
앱과 Mac의 로컬 데이터를 삭제해도 이미 키보드에 적용한 시계·조명 상태는
되돌아가지 않습니다. 특히 내장 모드 조절값은 정확한 사전 readback이나 자동
rollback을 지원하지 않으므로 앱 삭제를 복원 방법으로 사용하면 안 됩니다.

## 안전 경계

현재 공개 빌드는 다음 원칙을 지킵니다.

- 기본 검사는 공개 IOHID 레지스트리 속성만 열거
- 명시적 수동 진단만 exact vendor collection을 열어 `GetReport` 수행
- 키별 F5 조회와 시계·내장 모드 하나·완성된 84키 RGB 적용은 각각 별도 확인 필요
- 장치 작업 전후 exact identity와 네 컬렉션을 다시 검증
- 명령과 ACK 사이 35ms 간격, 각 비동기 Feature 작업 360ms 제한, ACK byte 3 검증
- 어떤 장치 작업도 자동 재시도하지 않음
- 읽은 원시 report를 파일·로그·프로필에 저장하지 않음
- 하드웨어 쓰기는 기본 거부하고 확인된 세 작업만 형식화된 값으로 허용
- 임의 `SetReport`, output 전송, LCD·키맵·매크로 쓰기 및 seize 구현을 포함하지 않음
- trace 분석은 오프라인 파일 입력으로만 제한
- trace 출력은 label·원본 timestamp·payload 값 없이 집계와 byte offset만 제공
- trace public encoder, 실시간 캡처 및 report 재생 API를 포함하지 않음
- 펌웨어와 부트로더 기능은 프로젝트 범위에서 제외

이 저장소에는 제조사 EXE, 설치 파일, DLL, 펌웨어, 업데이트 도구, 추출물,
로고, UI 화면 또는 기타 제조사 자산을 포함하지 않습니다. 앱 마크와 인터페이스는
프로젝트가 독립적으로 제작했습니다.

## 기여

기여 전 다음 문서를 확인해 주세요.

- [기여 안내](CONTRIBUTING.md)
- [클린룸 정책](CLEAN_ROOM.md)
- [설계 및 안전 경계](DESIGN.md)
- [보안 정책](SECURITY.md)
- [공지 및 상표 안내](NOTICE.md)
- [변경 기록](CHANGELOG.md)

공개 문서와 재현 가능한 최소 장치 관찰만 사용해 주세요. 제조사 바이너리,
펌웨어, 디컴파일 결과, 비공개 자료, 원본 캡처 또는 재배포 권리가 없는 자산은
이슈와 PR에도 첨부하지 않습니다.

## 라이선스

KeyCanvas가 독자적으로 작성한 코드와 문서는 [MIT License](LICENSE)로
배포합니다.

MIT 라이선스는 제3자의 상표, 펌웨어, 소프트웨어 또는 자산에 대한 권리를
부여하지 않습니다.

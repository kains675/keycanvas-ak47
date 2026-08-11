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
> 표를 적용할 수 있습니다. 현재 RGB를 읽는 별도의 F5 단발 질의도 매번 확인 후에만
> 실행됩니다. 기본값 복원은 counts/page risk dry-run 검사만 제공합니다. LCD는
> 기본 비활성 상태에서 프로젝트가 만든 고정 모서리 4색 1프레임 진단부터 시작합니다.
> 새 build에서 그 결과와 USB cable 전원 제거 복구 순서를 영속 receipt로 모두
> 검증한 exact 대상만, 현재 editor의 불변 snapshot을 1…40프레임 범위에서 별도
> exact-plan 확인 후 적용할 수 있습니다. 과거 실기 결과는 권한으로 가져오지 않습니다.

## 지금 할 수 있는 것

- macOS용 독립 SwiftUI 인터페이스
- 한국어·영어 전환
- Dashboard, Keymap, Lighting, Macros, Display, Settings 화면
- 84키 Base/Fn 키맵 초안 편집
- AK47 non-PRO에서 확인된 19개 내장 조명 모드의 로컬 선택과 실제 84키 형상의
  상태 기반 논리 미리보기
- 실제 84키 위치와 RGB 슬롯을 사용하는 키별 색상 페인터
- 유효성을 검사하는 매크로 초안
- 240×135 디스플레이 구성과 전체 GIF 프레임 재생·탐색
- GIF 프레임 추가·삭제·복제·순서·지연·crop/fit/fill/stretch, 간단한 bitmap
  text·pen 편집과 편집 GIF 내보내기
- 240×135 opaque RGB565 프레임, 256바이트 header, `0xFF`로 채운 4096바이트
  page로 이루어진 검증된 LCD 컨테이너의 **로컬 파일 내보내기**
- exact `bcdDevice 0x0115` 대상에서만 별도 확인 후 실행하는 고정 모서리 4색
  1프레임·16페이지 LCD 진단 전송(기본 비활성)
- 새 receipt build에서 고정 진단의 host 결과·모서리 육안 확인·USB-mode cable
  분리 상태의 real absence·원래 포트 exact4 재등장·완전 무전원 사용자 확인을
  순서대로 마친 exact 대상에 한해, 현재 editor의 불변 1…40프레임 snapshot을
  SHA-256·주소·페이지·지연 변환까지 확인하고 한 번 적용하는 자격 기반 LCD 경로
- Windows의 `Archon AK47 Driver Files` 백업에서 로컬 프로필과 LCD 레이어 가져오기
- 설정값 로컬 저장과 검증된 JSON 가져오기·내보내기
- 연결된 AK47 HID 컬렉션의 읽기 전용 메타데이터 확인
- 사용자가 직접 누를 때만 실행되는 feature/output `GetReport` 진단
- 사용자가 별도 확인한 뒤 한 번만 실행하는 현재 키별 RGB 조회
- 사용자가 작업별 확인을 거친 뒤 실행하는 시계 동기화
- 0–19번 중 현재 선택한 내장 모드 하나와 그 조절값의 단발 적용
- 누락 없이 완성된 84키 RGB 표와 밝기의 단발 적용
- 기능 설정·키별 RGB·내장 조명의 작업/ACK 수와 page risk만 보여 주는
  **비실행 dry-run 기본값 risk 검사**
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
여부도 같은 Windows 앱에서 확인한 값입니다. 미리보기는 Keymap과 같은 672×226
캔버스, 실제 84키 형상과 확인된 `lightIndex` 대응을 공유하며 고정 길이 84키
프레임을 만드는 로컬 상태 기계로 재생합니다. 반응형으로 분류한
2·3·13·14·15번 모드는 키를 클릭하거나 고정 순서의 합성 입력으로 반응을 볼 수
있습니다. 입력의 down/up 순서와 겹치는 파동 상태도 화면 안에서만 처리되며 HID
명령을 보내지 않습니다.

효과의 이동 축·누적/파동 구조·반응형 입력 규칙에는 권한 있는 로컬
상호운용성 분석에서 얻어 독립적으로 다시 표현한 최소 기능 사실을 사용했습니다.
공개 앱은 펌웨어나 private emulator를 포함하거나 실행하지 않습니다. 화면 재생
속도, 1–5단계 속도 보정, 밝기·색상 곡선, 합성 팔레트와 실제 스위치 아래의 광학
표현은 KeyCanvas가 만든 시각화입니다. 따라서 움직임 구조가 이전의 이름 기반
추정보다 구체적이지만, 픽셀·절대 시간·색감이 특정 펌웨어 revision과 정확히
일치한다고 주장하지 않습니다. 조명을 끄는 상태는 별도 효과로 만들지 않고
프로필의 `enabled` 값으로 저장합니다. 편집값은 조명 화면의 해당 적용 버튼을
누르고 별도 확인을 마친 경우에만 한 번 전송됩니다.

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

GIF 편집기는 로컬 복사본에서만 작업하며 원본 파일을 덮어쓰지 않습니다. 장치용
컨테이너는 완전히 합성한 240×135 프레임을 little-endian RGB565로 변환하고,
1…140프레임·최대 2215페이지·0…511ms source delay와 header/page padding을
검사합니다. 이 범위는 host-side 소프트웨어 ceiling일 뿐 키보드의 실제 SPI
partition 끝이나 안전한 복구 가능 용량을 증명하지 않습니다. live 전송은 이 범위와
분리되어 있으며 새 durable qualification의 시작은 프로젝트가 직접 만든 1프레임
진단 fixture 하나로만 제한됩니다.
240×135 검정 바탕에 좌상 빨강·우상 초록·좌하 파랑·우하 흰색 32×32 블록이
있고, 정확히 16×4096바이트 page와 SHA-256
`312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec`를 가져야
합니다. 현재 화면 readback·backup·rollback은 여전히 없으며, 로컬 컨테이너
내보내기가 진단 전송을 승인하지 않습니다. evidence-only macOS 실기에서 16개
Output 완료/예상 input sequence·commit·postflight와 네 모서리 표시를 확인했지만,
production receipt 이전 결과이므로 40프레임 권한으로 import·backfill하지 않습니다.
새 build의 receipt는 처음부터 비어 있으며, 새 고정 진단 성공·모서리 육안 확인·
selector를 USB 위치에 둔 cable 분리와 real absence·같은 원래 포트의 exact4
재등장·LCD/LED/장치 완전 무전원 사용자 확인을 순서대로 기록해야 합니다. 이후에만
현재 in-memory editor 값을 복사한 1…40프레임 snapshot을 별도 일회용 승인으로
보낼 수 있습니다. host sequence 완료 뒤에도 불변 예상 animation과 실제 LCD를
비교해 정확함을 기록하기 전까지 자격은 다시 잠기며, 틀리거나 확인할 수 없으면
영속 자격을 폐기하고 장치를 quarantine합니다.

## 아직 할 수 없는 것

- 키맵, 매크로 또는 일반 장치 설정을 실제 키보드에 적용
- 제한 subset을 포함한 모든 live 공장초기화·기본값 복원
- 시계, 선택한 내장 조명 하나, 완성된 84키 RGB, 고정 LCD 진단과 자격을 마친
  exact editor snapshot 이외의 설정 변경 또는 임의 `SetReport`
- durable qualification 없이 2프레임 이상을 보내거나, 40프레임을 넘기거나,
  raw/임의 payload를 직접 보내는 LCD live output
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
`bcdDevice`는 USB descriptor의 release 번호로만 사용하며, 그 값만으로 설치된
펌웨어 버전이나 MCU 종류를 확정하지 않습니다.

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

키별 RGB 조회와 제한된 장치 적용은 서로 독립된 확인 창을 거치는 단발
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

확인 후 실행할 수 있는 장치 적용 범위는 다음 세 종류뿐입니다.

- 현재 Mac의 로컬 날짜와 시각을 첫 번째 화면 시계 슬롯에 동기화
- `LED Off`를 포함한 0–19번 중 현재 선택한 내장 조명 모드 하나와 색상·밝기·
  속도·방향 적용
- 검증된 84개 `lightIndex`가 정확히 한 번씩 들어 있는 전체 키별 RGB 표와 밝기
  적용

### 고정 LCD 1프레임 최초 실기

LCD 진단은 위 Feature 적용 목록과 분리된 기본 비활성 예외입니다. exact target의
FF13 64-byte command collection과 FF68 input 64/output 4096 collection이 각각
하나일 때만, 현재 이미지 덮어쓰기·readback/rollback 없음·다른 utility/VM
종료·USB-mode cable removal recovery 준비의 4가지 risk 확인과 고정 fixture에 묶인
별도 destructive 일회용 확인을 소비합니다. fixture hash·1프레임·
16페이지 중 하나라도 다르면 report를 보내지 않습니다. 한 번 시작하면 4096바이트
Output 16개를 각각 한 번만 제출하고, 각 Output 완료 뒤 예상한 64바이트 input
report가 하나씩 오는지 확인한 뒤 commit과 exact topology postflight를 수행합니다.
실패 시 자동 재시도·resume은 없습니다.

macOS IOHID에서 report ID `0`은 별도 argument로 전달하며 Feature/Input
버퍼는 정확히 64바이트, Output는 4096바이트입니다. 버퍼 앞에 ID용 `00`을
추가하지 않습니다. command pacing은 35ms, Output 뒤 input wait는 300ms로
제한하고 input report의 ID 0·64바이트·prefix `01 5A 02`를 모두 검증합니다.
Output 완료 또는 다음 input 검증이 실패하면 commit하지 않고 자동 재시도나
추가 `0xF0` finalize를 보내지 않습니다.

권한 있는 개인 Windows 성공 capture에서 FF13은 interface `MI_03`, FF68은
`MI_02`, Output endpoint는 `0x03`, input endpoint는 `0x84`로 관찰됐습니다. 원본
capture와 payload는 이 저장소에 포함하지 않습니다. macOS adapter는 IORegistry
ancestry를 직접 검사해 FF13이 `bInterfaceNumber 3`, FF68이 `bInterfaceNumber 2`이고
두 collection이 같은 exact physical USB parent·identity에 속하는지 강제합니다.
다만 IOHID는 numeric endpoint `0x03/0x84`를 직접 선택하거나 관찰하지 않으므로,
macOS에서 해당 endpoint를 직접 계측했다고 주장하지 않습니다.

offline 140프레임·2215페이지 ceiling은 live 허용량이 아닙니다. 고정 fixture의
macOS 근거 수집 실기에서는 16개 Output 완료가 모두 예상 input sequence를
유도했고 commit과 exact topology postflight가 끝났으며, 사용자가 빨강·초록·파랑·
흰색 네 모서리의 위치와 방향을 직접 확인했습니다. 이어 selector를 USB 위치에
둔 채 cable을 분리해 LCD·LED와 장치가 완전히 꺼지고 real enumeration이 0이 된
상태와, 같은 원래 Mac USB location에서 exact 4 collection이 재등장한
상태도 순서대로 확인했습니다. 2.4G/Bluetooth 전환은 이 복구를 대신하지 않습니다.
그러나 이 실기는 production receipt build보다 먼저 수행된 evidence일 뿐이며
authority로 import·backfill할 수 없습니다. 1…40프레임 자격에는 새 build에서 고정
1프레임을 다시 성공시키고 exact target·fixture digest·16 host sequence·육안 확인·
복구 provenance를 Core 영속 receipt로 새로 기록해야 합니다. 그 전까지 bootstrap
1프레임만 실행 가능하고 qualified editor Apply는 완전히 잠깁니다.

16개 sequence는 각 Output 완료 뒤 예상한 ID·길이·prefix의 input report가
왔다는 근거일 뿐입니다. input에는 page index가 없으며 page 수락, LCD readback,
external-flash 무결성, 실제 색·방향 표시, 40프레임 용량을 증명하지 않습니다.
전송 중 idle sleep을 줄이는 process activity를 사용하지만 전원 유실, force quit,
사용자가 시작한 sleep/shutdown, 다른 utility·VM·HID client의 개입 위험은
남아 있습니다.

최초 실기는 다음 순서로만 진행합니다.

1. Windows 제조사 utility, USB/HID tool과 USB를 사용하는 VM을 완전히
   종료하고 Mac의 sleep/shutdown을 시작하지 않습니다.
2. 키보드를 유선으로 연결한 뒤 Device Inspector에서 revision `0x0115`와 정확한
   4-collection topology, quarantine 없음을 확인합니다.
3. Display의 **LCD 실기 전송** card에서 4가지 risk를 모두 확인한 뒤
   **1프레임 실기 승인…**과 별도 destructive 확인을 누릅니다.
4. 전송 중 케이블·전원·앱을 건드리지 않고 expected input이 `16 / 16`이 되는지
   확인합니다. 실패하면 재시도하지 않습니다.
5. 성공 표시 후 LCD의 네 모서리 색·위치·방향을 직접 확인하고 이 사실을 exact
   fixture에 묶어 명시적으로 기록합니다. 이 육안 확인 전에는 올바른 표시 결과를
   주장하지 않습니다.
6. selector를 USB 위치에 둔 채 cable을 분리해 LCD·LED와 장치가 완전히 꺼지고
   Device Inspector의 real enumeration이 0이 되는지 확인합니다. 2.4G/Bluetooth
   전환은 복구가 아닙니다.
7. selector를 계속 USB 위치에 둔 채 같은 원래 Mac USB 포트에 재연결하고,
   동일 identity·revision·exact 4 collection 재등장을 확인한 뒤 실제 cable-removal
   복구를 수행했다는 별도 사용자 attestation을 기록합니다.
8. Core가 위 전체 provenance를 영속 receipt로 검증하지 못하면 1…40프레임 editor
   Apply를 열지 않습니다. 검증 뒤에도 현재 in-memory 편집을 복사한 불변 snapshot의
   exact target·SHA-256·frame/page/byte/address/delay를 보여 주는 별도 일회용
   authorization이 필요합니다. raw payload와 40프레임 초과 전송은 계속 잠깁니다.
9. qualified host sequence가 끝나도 즉시 성공으로 확정하지 않습니다. 실제 제출한
   RGB565 바이트의 불변 preview와 키보드 LCD를 비교해 정확함을 기록해야 자격이 다시
   열립니다. 틀리거나 확인 불가이면 durable quarantine과 자격 폐기로 진행합니다.

기존 성공 실기의 화면·host 결과와 복구 관찰은 설계 근거로만 사용합니다. 새
receipt build는 빈 상태에서 시작하며 수동 migration, 과거 결과 backfill 또는
일반 UI bypass를 제공하지 않습니다. 따라서 한 번의 새 고정 1프레임 실기부터
위 순서를 다시 완료하기 전에는 40프레임이 열리지 않습니다.

### 명시적 장치 작업 공통 경계

각 작업은 종류가 일치하는 확인 기록이 있어야 시작됩니다. F5와 세 Feature
적용은 유선 FF13만 비독점으로 열고, LCD bootstrap/qualified 전송은 FF13과 FF68을 각각
하나씩 비독점으로 엽니다. 적용 작업은 각 명령과 필요한 ACK 사이에 35ms
간격을 둡니다.
비독점 연결이므로 KeyCanvas의 cross-process lock은 다른 KeyCanvas 인스턴스만
막을 수 있습니다. 제조사 유틸리티, Windows VM, USB/HID 디버거 등은 동일한
FF13 컬렉션에 개입할 수 있으므로 F5·시계·조명·RGB 확인 전에 해당
프로그램과 VM을 완전히 종료하세요. LCD 전송 확인 전에도 같은 조건이
필요합니다.
비동기 Feature 작업은 각각 360ms로 제한되고, ACK가 필요한 단계는 64바이트
응답의 byte 3이 성공값인지 검사합니다. 실패하면 즉시 중단하며 자동 재시도,
임의 raw payload, 자격 없는 LCD·40프레임 초과 LCD·키맵·매크로 전송, 원시 report 로그,
펌웨어·부트로더 작업은 없습니다. 적용 작업은 종료 뒤에도 동일한 네 컬렉션이
남아 있는지 다시 확인합니다.

Settings의 기본값 항목은 기능 설정·키별 RGB·내장 조명 category의 **작업/ACK
수와 page risk만 pure dry-run으로** 보여 줍니다. raw step이나 default payload는
포함하지 않습니다. Base/Fn 키맵, 매크로, LCD는 차단되며 HID 명령을 보내는
adapter나 StudioModel 실행 경로가 없습니다. preflight는 서로 다른 내부 flash
4개 page에 걸친 7회의 erase/program
transaction을 표시하지만, 이는 static protocol 근거입니다. private emulator는
global persistence helper의 실제 flash side effect를 검증하지 않습니다. 따라서 이
기능은 전체 공장초기화나 복구 도구가 아닙니다.

### 부분 전송 실패와 quarantine 해제

F5 질의, 세 가지 Feature 적용과 LCD 진단 전송은 첫 HID report 전에 target
identity만 담은 write-ahead marker를 다음 위치에 atomic 저장하고 파일과 상위
directory를 `fsync`합니다.

```text
~/Library/Application Support/KeyCanvas/ak47-device-quarantine-v1.json
```

marker에는 VID/PID, 제품명, location, revision과 선택적 serial만 들어가며 report,
설정값, 이미지나 펌웨어는 저장하지 않습니다. marker를 안전하게 기록할 수 없으면
report를 보내지 않고 장치 작업을 차단합니다. report가 하나라도 제출된 뒤 실패하거나
cancel 완료를 확인하지 못하거나 postflight가 실패하면 키보드가 일부만 변경됐을 수
있으므로 marker를 유지합니다. 앱을 다시 실행해도 marker는 남고 자동 재시도하지
않습니다. marker는 backup이나 rollback 데이터가 아닙니다.

안전한 해제 중에는 같은 폴더의
`ak47-device-quarantine-v1.json.pending-clear`에 기존 identity를 먼저 저장하고,
primary JSON에는 빈 배열 `[]`을 durable clear receipt로 남깁니다. 앱은 두 파일의
identity 합집합을 격리 상태로 읽으며, staged 파일 제거·directory `fsync`가 실패하면
기존 identity를 복원하고 오류를 표시합니다. storage 자체의 절대적인 고장까지
소프트웨어가 보장할 수는 없습니다.

해제하려면 한 번의 앱 실행 안에서 다음 순서를 모두 마쳐야 합니다.

1. 키보드 전원 switch를 완전히 끄고 유선 케이블을 분리합니다.
2. Device Inspector에서 새로고침해 marked target이 0 collection으로 완전히 사라진
   상태를 관찰합니다.
3. 유선으로 다시 연결하고 새로고침해 같은 identity의 정확한 네 collection이
   돌아온 것을 확인합니다. serial을 제공하지 않는 장치는 원래
   location으로 돌아와야 하므로 같은 Mac USB port에 다시 연결하세요.
4. 전원을 완전히 끈 뒤 유선 전원을 다시 연결했다는 최종 문구를 사용자가 직접
   확인합니다.

앱은 absence와 재등장은 확인하지만 실제 전원 switch가 꺼졌는지는 전기적으로
검증할 수 없어 마지막 단계는 사용자 확인에 의존합니다. 중간에 앱을 재실행하면
marker는 유지되지만 두 관찰 기록은 사라지므로 1–4단계를 다시 해야 합니다.
marker나 앱 데이터를 삭제하거나 앱을 재설치하는 것은 키보드 복구가 아니며 이
안전장치만 우회할 수 있으므로 복구 방법으로 사용하지 마세요. 실패 후
앱 재실행, handle close 또는 전원 switch를 끄지 않은 단순 USB 재연결도
복구로 간주하지 않습니다.

ACK는 명령 수신을 뜻할 뿐 화면이나 조명 결과를 일반적으로 readback해 검증하는
기능은 아닙니다. 특히 내장 모드·밝기·속도·방향의 현재값을 읽거나 적용 전 상태로
정확히 되돌리는 경로는 없습니다. 84키 RGB만 별도의 F5 질의로 다시 읽을 수
있습니다. 따라서 장치 적용 기능은 여전히 실험적이며 작업 전 현재 상태를 직접
확인해야 합니다.

실기 적용 경로는 기본 테스트에서는 건너뛰며 작업별 확인 문구가 있을 때만
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

장치가 quarantine 상태라면 삭제하기 전에 위 복구 순서를 완료하세요. 앱이나 marker
삭제는 키보드 복구가 아닙니다.

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
장치가 quarantine 상태라면 위 복구 순서를 먼저 완료하세요. `KeyCanvas` 폴더를
삭제하면 marker도 함께 없어지지만 키보드 상태는 복구되지 않습니다.

## 안전 경계

현재 공개 빌드는 다음 원칙을 지킵니다.

- 기본 검사는 공개 IOHID 레지스트리 속성만 열거
- 명시적 수동 진단만 exact vendor collection을 열어 `GetReport` 수행
- 키별 F5 조회, 시계·내장 모드 하나·완성된 84키 RGB, 고정 LCD bootstrap과
  자격을 마친 exact editor snapshot은 각각 별도 확인 필요
- 장치 작업 전후 exact identity와 네 컬렉션을 다시 검증
- 명령과 ACK 사이 35ms 간격, 각 비동기 Feature 작업 360ms 제한, ACK byte 3 검증
- 어떤 장치 작업도 자동 재시도하지 않음
- F5/Feature/LCD report 전에 target별 durable marker를 기록하고, 제출 뒤 실패 시
  재실행 뒤에도 해당 target 작업을 quarantine
- 앱 종료·중단 뒤 남은 LCD transfer lease는 다른 모든 장치 작업을 차단하며, 다른
  KeyCanvas process가 실행 중이 아님을 확인한 경우에만 durable quarantine과 자격
  폐기로 reconcile하고 성공으로 복원하지 않음
- Device Inspector가 absence→동일 exact topology 재등장을 관찰하고 사용자가
  selector를 USB 위치에 둔 cable 분리 완전 무전원·원래 포트 재연결을 명시 확인한
  뒤에만 staged durable clear 수행
- 읽은 원시 report를 파일·로그·프로필에 저장하지 않음
- 기본값 계획은 pure dry-run이며 live restore adapter가 없음
- GIF 편집과 RGB565 컨테이너 파일 내보내기는 로컬에서만 수행하며 그 자체로
  장치 승인을 만들지 않음
- LCD bootstrap은 exact target·고정 1프레임 SHA·16페이지에 하드 제한하고,
  qualified Apply는 Core의 fresh 영속 receipt와 불변 1…40프레임 exact plan에 제한
- LCD host 완료 뒤 exact submitted RGB565 preview 육안 확인 전에는 자격을 다시
  열지 않으며, 틀림/확인 불가는 quarantine과 자격 폐기로 처리
- 자동 재시도·readback·backup·rollback, 임의 `SetReport`, arbitrary raw payload,
  40프레임 초과 LCD·키맵·매크로 live 쓰기 및 seize 금지
- trace 분석은 오프라인 파일 입력으로만 제한
- trace 출력은 label·원본 timestamp·payload 값 없이 집계와 byte offset만 제공
- trace public encoder, 실시간 캡처 및 report 재생 API를 포함하지 않음
- 펌웨어와 부트로더 기능은 프로젝트 범위에서 제외

이 저장소에는 제조사 EXE, 설치 파일, DLL, 펌웨어, 업데이트 도구, 추출물,
private firmware-backed emulator, default GIF, 로고, UI 화면 또는 기타 제조사
자산을 포함하지 않습니다. 앱 마크와 인터페이스는 프로젝트가 독립적으로
제작했습니다. 일부 최소 호환성 사실은 권한 있는 로컬 interoperability 분석에서
얻어 독립적으로 다시 표현했으므로, 엄격한 two-team clean-room을 주장하지 않습니다.

## 기여

기여 전 다음 문서를 확인해 주세요.

- [기여 안내](CONTRIBUTING.md)
- [소스·interoperability 경계](CLEAN_ROOM.md)
- [설계 및 안전 경계](DESIGN.md)
- [보안 정책](SECURITY.md)
- [공지 및 상표 안내](NOTICE.md)
- [변경 기록](CHANGELOG.md)

공개 자료, 재현 가능한 장치 관찰 또는 독립적으로 다시 표현하고 검토한 최소
interoperability 사실만 public 구현에 사용해 주세요. 제조사 바이너리·펌웨어·
disassembly/decompilation 결과·private emulator·비공개 자료·원본 캡처·default GIF나
재배포 권리가 없는 자산은 이슈와 PR에도 첨부하지 않습니다. public test에는
새로 만든 합성 데이터만 사용합니다.

## 라이선스

KeyCanvas가 독자적으로 작성한 코드와 문서는 [MIT License](LICENSE)로
배포합니다.

MIT 라이선스는 제3자의 상표, 펌웨어, 소프트웨어 또는 자산에 대한 권리를
부여하지 않습니다.

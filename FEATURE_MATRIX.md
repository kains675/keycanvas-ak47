# KeyCanvas 기능 매트릭스

이 문서는 ARCHON AK47 non-PRO용 Windows 설정 도구에서 사용자가 접할 수 있는
기능 범주와 현재 KeyCanvas 구현 범위를 비교한 개발 목록입니다. 비교 대상의
기능명과 동작 범위만 독립적인 문장으로 요약했습니다. 일부 최소 기능 사실은
합법적으로 보유한 로컬 환경의 interoperability 분석에서 얻어 독립적으로 다시
표현했지만, 제조사 코드·바이너리·UI·문구·이미지·GIF·펌웨어·private emulator와
원본 capture는 저장소에 포함하지 않습니다. 공개 테스트는 새로 만든 합성
데이터만 사용합니다. 이는 엄격한 two-team clean-room을 주장하는 문서가 아닙니다.

기준일은 2026-08-11입니다. 기본 장치 검사와 직접 report 진단은 읽기 전용입니다.
별도의 F5 키별 RGB 조회와 제한된 Feature 적용은 제품명 `Archon AK47`, 유선 USB
`0x0C45:0x800A`, `bcdDevice 0x0115`, FF13 Feature 채널과 네 HID 컬렉션의 전체
구성이 정확히 일치할 때만 실행됩니다. live 적용 범위는 시계 동기화, 0–19번 중
현재 선택한 내장 모드 하나, 검증된 84키 전체 RGB 표뿐입니다. 기능 설정·키별
RGB·내장 조명의 세 영역 기본값 risk model은 counts/page risk만 pure dry-run으로
표시하며 raw step/default payload와 HID 실행 경로가 없습니다. 이는 전체
공장초기화가 아닙니다. live 작업은 별도 확인이
필요하고, Feature 단계는 35ms 간격과 필요한 64바이트 ACK byte 3 검증을 사용하며
자동 재시도하지 않습니다. LCD concrete adapter의 bootstrap은 프로젝트가 만든
고정 1프레임·16페이지 진단 fixture만 받습니다. 새 Core 영속 receipt에서 전체
qualification 순서를 마친 exact 대상에는 현재 editor의 불변 1…40프레임 plan만
별도 exact 확인으로 허용합니다. production receipt는 비어 시작하고 과거 실기를
backfill하지 않으므로 그전까지 UI는 잠깁니다. 아래에서
“Windows 기능”은 호환성 목표를 식별하기 위한 기능 범주일 뿐, 같은 화면이나 사용
흐름을 복제한다는 뜻이 아닙니다.

## 표 읽는 법

- **구현**: 현재의 로컬 또는 명시적으로 제한된 장치 안전 경계 안에서 해당 범위를
  끝까지 사용할 수 있습니다.
- **부분 구현**: 독자 UI, 로컬 모델 또는 저장 기능은 있지만 세부 편집이나 장치
  동기화가 빠져 있습니다.
- **미구현**: 사용할 수 있는 동작이 아직 없습니다.
- **L — 로컬만**: 장치 없이 구현할 수 있습니다.
- **R — 장치 읽기**: 허용 범위와 공개 API를 먼저 검토한 읽기 경로가 필요합니다.
- **Q — 제한적 장치 질의**: 응답을 시작·종료하는 검증된 Feature 명령을 보내지만
  설정 적용은 하지 않습니다. 명시적 확인과 별도 안전 검토가 필요합니다.
- **W — 제한적 장치 쓰기**: exact target, 작업별 확인, 검증된 형식과 실패 중단
  경계가 필요합니다. ACK만으로 이전 상태의 백업이나 rollback이 보장되지는 않습니다.
- **U — 프로토콜 미상**: 독립적으로 재현 가능한 최소 사실과 합성 테스트가 먼저
  필요합니다. 추측한 report를 장치에 보내면 안 됩니다.

## Dashboard

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 연결 장치와 동작 모드 표시 | 대상 VID/PID의 HID 컬렉션 수와 연결 여부를 공개 레지스트리 속성으로 표시 | 구현 | 현재는 유선 대상만 식별 | R |
| 프로필 선택과 요약 | 로컬 프로필 수, 현재 프로필, 편집 화면 바로가기를 제공 | 부분 구현 | 프로필 복제·삭제·정렬과 변경 요약 | L |
| 무선/수신기 상태 | 없음 | 미구현 | 지원 대상 식별, 연결 모드와 배터리 상태의 의미 확인 | R + U |
| 장치의 현재 설정 요약 | 예시 카드만 있으며 실제 장치 상태로 표시하지 않음 | 미구현 | 키맵·조명·화면·매크로 상태의 안전한 읽기 | R + U |

## Keymap

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 기본/Fn 레이어와 물리 키 선택 | 독자적으로 작성한 84키 캔버스에서 Base/Fn 로컬 초안을 편집하고 JSON 프로필에 저장 | 부분 구현 | 확인된 장치 위치 번호와 Fn 편집 가능 범위를 로컬 모델에 반영 | L |
| 일반 키·사용 안 함·미디어 동작 | 일반 HID 키, 사용 안 함, 일부 consumer-control 동작을 로컬 모델에 저장. 알려지지 않은 HID/consumer 값도 hex로 표시하고 기존 할당을 선택 목록에서 잃지 않음 | 부분 구현 | 전체 키 목록, 검색, 원래 값 복원, 더 세밀한 유효성 안내 | L |
| 매크로·마우스·시스템·앱/웹·텍스트·다중 키 할당 | 프로필의 매크로를 Base/Fn 키 할당 선택기에 연결하고 이름 또는 누락된 identifier를 표시·로컬 round-trip. 아직 알지 못하는 기존 할당도 편집 진입만으로 덮어쓰지 않음 | 부분 구현 | 마우스·시스템·앱/웹·텍스트·다중 키 동작 편집기와 macOS 의미 정의 | L |
| 현재 장치 키맵 읽기 | 없음 | 미구현 | 보고서 형식과 revision 검증 | R + U |
| 키맵 적용 | 의도적으로 없음 | 미구현 | 원자적 적용, 검증, 되돌리기와 안전 검토 | W + U |

## Lighting

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 효과·밝기·속도·색상 | 확인된 ID 1–19와 별도 끄기(모드 0), 모드별 조절 가능 항목, 1–5단계 밝기·속도, 방향과 단색/컬러풀 값을 로컬 프로필에서 편집. 실제 84키 형상에서 최소 이동 구조·누적 상태·반응형 down/up 규칙을 독립 구현한 정수 상태 미리보기를 재생하며, 별도 확인 뒤 현재 선택한 모드 하나만 유선 장치에 적용. 실기에서 `Static`(1)과 `Launch`(14) 단발 적용 성공 | 부분 구현 | 미리보기의 30Hz 재생 속도·밝기/색상 곡선·합성 팔레트·광학 표현은 KeyCanvas 보정값이며 pixel/time/revision-exact를 주장하지 않음. 적용 전 모드·밝기·속도·방향 readback/rollback도 없음. 미리보기 자체는 HID 명령을 보내지 않음 | L + W; 육안 검증 U |
| 키별 사용자 조명 | 실제 84키와 확인된 `lightIndex`에서 키 선택·칠하기·전체 채우기·선택/전체 지우기를 로컬 프로필에 저장. 84키가 모두 채워진 경우에만 별도 확인 뒤 전체 표와 밝기를 한 번 적용. 실기에서 밝기 3의 84키 3색 표 적용과 키 배치 보존 확인 | 부분 구현 | 다중 선택·프리셋과 적용 전 자동 백업/rollback은 없음. F5 결과는 원본 RGB가 아니라 밝기 조정값이어서 byte-exact 백업으로 사용할 수 없음 | L + W + Q |
| 실시간/음악 반응 조명 | 없음 | 미구현 | 로컬 시뮬레이션, 오디오 권한과 개인정보 안내 | L |
| 현재 키별 RGB 읽기 | exact 유선 USB identity와 네 컬렉션을 다시 검사한 뒤 확인된 단발 질의를 수행하고 9×64바이트 응답에서 84키 RGB를 메모리에만 표시 | 부분 구현 | 첫 실기는 84키 모두 0. 사용자가 14번 `Launch`로 바꿨다고 별도로 알려준 뒤의 한 시점에는 84키 모두 0이 아니며 24개 색이었음. KeyCanvas도 Windows 리소스 이름을 그대로 표시함. 응답 자체에는 모드 ID·정확한 움직임 공식·밝기·속도·방향이 없으며 다른 revision은 미확인 | Q + R |
| 조명 효과·밝기·속도 읽기 | 없음. 내장 모드 적용 ACK는 현재 파라미터 readback이 아님 | 미구현 | 상태 응답 형식과 안전한 이전 상태 백업·복구 검증 | R + U |

## Macros

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 매크로 목록·이름·반복 | 빈 프로필을 예제 없이 그대로 열고, 새 빈 매크로 또는 명시적 예제를 추가. 이름·반복 횟수 편집, 새 identifier로 복제, 삭제를 제공하며 Keymap에서 참조 중인 매크로 삭제는 차단 | 구현 | 검색·정렬과 참조 위치 바로가기 | L |
| 키 입력과 지연 편집 | 제한된 키 탭과 지연을 추가하고 event 삭제·위/아래 순서 이동을 지원. 지연은 1…60,000ms로 직접 편집하며 범위와 profile validation 오류를 저장 전에 표시 | 부분 구현 | 개별 key-down/up의 key code 직접 변경과 다중 선택 편집 | L |
| 키보드/마우스 기록 | 없음 | 미구현 | 명시적 녹화 상태, macOS 권한, 민감 입력 제외 정책 | L |
| 반복·재생 방식과 파일 교환 | 반복 횟수와 event를 로컬 프로필에 저장하고 빈 목록·정의·Keymap 참조의 round-trip을 검증 | 부분 구현 | 누르는 동안/토글/횟수 재생 의미, 매크로 단위 가져오기·내보내기 | L |
| 키 할당과 장치 적용 | Keymap에서 매크로를 Base/Fn 키에 할당하고 저장하며, 누락 참조를 표시하고 참조 중 삭제를 차단 | 부분 구현 | 장치 적용은 없음. 장치 용량·event 제한, 전송 형식, 되돌리기 검증 필요 | L, 이후 W + U |

## Display

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 240×135 화면 구성 | 독자 SwiftUI 도형으로 문구·강조색·시계·배터리 예시를 로컬 미리보기하고 프로필에 저장 | 부분 구현 | 정확한 글꼴/합성 결과의 파일 렌더링과 레이어 편집 | L |
| PNG/JPEG/GIF 불러오기 | 파일 내용을 ImageIO로 다시 확인하고 240×135 캔버스에서 정지 이미지 또는 전체 GIF 프레임을 재생·탐색 | 구현 | 색 관리와 더 정밀한 재생 진단 | L |
| 이미지 메타데이터 | 원본 픽셀 크기·프레임 수·지연·재생 시간과 로컬 컨테이너 예상치를 표시하며 과도한 크기·프레임 수·파일 용량·작업량을 거부 | 구현 | 색 공간 표시와 decode 메모리 진단 | L |
| 자산 보관과 재생 목록 | 원본은 바꾸지 않고 앱 전용 폴더에 고유 이름으로 복사해 프로필 `assets`/`playlist`에 연결하고 순서 이동·목록 제거를 지원 | 구현 | 사용하지 않는 로컬 복사본 정리와 다중 선택 | L |
| 이미지 내보내기 | 선택한 로컬 복사본을 사용자가 고른 위치로 내보냄 | 구현 | 이름 충돌 안내와 여러 파일 내보내기 | L |
| Windows 로컬 화면 자산 가져오기 | 사용자가 선택한 `Archon AK47 Driver Files` 폴더의 SQLite DB를 읽기 전용으로 제한 조회하고, 검증된 PNG 레이어의 원본 픽셀 크기·순서·delay를 보존한 GIF와 독자 프로필로 가져옴 | 구현 | 여러 레이어 재생 순서 편집과 가져오기 미리보기 | L |
| 프레임·그리기·텍스트 편집 | GIF 프레임 추가·삭제·복제·순서 이동, 0…511ms 지연, crop/fit/fill/stretch, 독자 bitmap text·pen 편집과 GIF 내보내기 | 구현 | undo/redo, 다중 프레임 일괄 편집, 고급 도구 | L |
| 240×135 RGB565 컨테이너 | 완전히 합성한 opaque 프레임을 little-endian RGB565로 만들고 256바이트 header와 `0xFF`로 채운 정확한 4096바이트 page를 로컬 파일로 내보냄. 1…140프레임·최대 2215페이지와 지연 byte wrap을 검증 | 구현 | 이 host-side ceiling은 물리 SPI partition 끝이나 안전한 장치 용량을 증명하지 않음 | L |
| 시간 동기화 | 장치 검사기에서 별도 확인 뒤 현재 Mac의 로컬 날짜·시각을 첫 번째 시계 슬롯에 한 번 전송. ACK가 정의된 단계를 검증하고 자동 재시도하지 않음. 수정된 트랜잭션의 단발 실기 성공 | 부분 구현 | 장치의 현재 시각 readback, 정확한 이전 값 복원과 자동 rollback, 화면의 육안 시각 확인은 없음 | W |
| LCD 이미지 장치 전송 | 고정 모서리 4색 1프레임·16페이지·exact SHA bootstrap과, Core의 target-bound durable qualification을 모두 마친 뒤 현재 in-memory editor 값을 복사한 불변 1…40프레임 exact plan을 보내는 별도 경로를 구현. final sheet가 target/frame/page/bytes/address/SHA/delay를 표시하고 일회용 승인을 plan에 bind | 실험적 부분 구현 | production receipt는 빈 상태에서 시작하고 과거 실기를 import/backfill하지 않음. bootstrap host 성공→모서리 육안 확인→USB-mode cable removal real absence→원래 port exact4 재등장→완전 무전원 attestation 순서를 강제. 각 qualified host 성공 뒤에도 exact submitted RGB565 preview 육안 확인 전에는 잠기며, 틀림/확인 불가는 retryable pending을 거쳐 quarantine+자격 폐기. readback/backup/rollback 없음, >40 live와 raw payload는 잠금 | W + U |
| 현재 화면 이미지 읽기 | 없음. 로컬 자산 미리보기는 장치 화면의 readback이 아님 | 미구현 | 장치가 화면 이미지 읽기를 지원하는지부터 알 수 없으며 개인정보·저작권 경계 확인 필요 | R + U |

## Settings

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 프로필 관리 | 새 프로필, 이름 변경, 로컬 저장, 검증된 JSON 가져오기·내보내기와 Windows 로컬 백업 가져오기 | 부분 구현 | 복제·삭제·정렬, 자산을 포함한 이식 가능한 묶음 형식 | L |
| 앱 언어와 작업 공간 | 한국어/영어 즉시 전환, 마지막 화면·안전 안내·시작 시 검사 설정 | 구현 | 정식 문자열 카탈로그와 접근성 검수 | L |
| 절전·디바운스·Fn 설정 | 장치로 보내지 않는 로컬 메타데이터 초안 | 부분 구현 | 실제 지원 범위와 단위 확인. 보고율 항목은 KeyCanvas 초안이며 Windows 호환성 주장 아님 | L, 이후 U |
| 제한된 기본값 risk 검사 | 기능 설정·키별 RGB·내장 조명 category의 SET/ACK count와 page risk만 pure dry-run으로 표시. raw step/default payload는 공개하지 않으며, 7회로 추정되는 internal-flash erase/program transaction이 서로 다른 4 page에 걸림 | 테스트/검사 전용 | HID 실행 경로 없음. 전체 공장초기화 아님. Base/Fn keymap·macro·LCD 제외. transaction/page 수는 static protocol 근거이며 global persistence의 실제 flash side effect는 emulator로 검증되지 않음 | U; live W 차단 |
| 잠금키·응답 단계 | 없음 | 미구현 | 상태 의미, 변경 범위, 복구 절차 확인 | R + W + U |
| 앱 자동 시작 | 없음 | 미구현 | macOS 로그인 항목과 명시적 사용자 동의 | L |
| 앱/장치 업데이트 | 없음 | 미구현 | 앱 업데이트는 별도 배포 설계가 필요. 펌웨어 업데이트·추출·플래시는 프로젝트 범위 밖 | L; 펌웨어 제외 |

## Device Inspector

| Windows 기능 범주 | KeyCanvas 현재 상태 | 상태 | 남은 범위 | 선행조건 |
| --- | --- | --- | --- | --- |
| 대상 장치 식별 | 유선 대상 VID/PID에 일치하는 공개 IOHID 레지스트리 컬렉션만 열거 | 구현 | hardware revision 식별에 쓸 수 있는 공개 속성 검토 | R |
| HID 컬렉션 메타데이터 | usage, report 크기 등 레지스트리 메타데이터를 읽기 전용으로 표시 | 구현 | 진단 내보내기 시 serial/location 제거 정책 | R + L |
| 수신기·무선·배터리 정보 | 없음 | 미구현 | 별도 식별자와 공개 속성 존재 여부를 독립적으로 확인 | R + U |
| feature/output report 직접 읽기 | 사용자가 누른 경우에만 정확한 64-byte feature 및 4096-byte output 후보에 단발 `GetReport`를 수행하고 길이·0이 아닌 바이트 수만 표시 | 부분 구현 | 현재 feature 결과는 전부 0이며 output GET은 pipe stall. selector 없는 GET으로는 백업 불가 | R |
| selector 기반 상태 질의 | 키별 RGB에 한해 F5 질의, 9개의 64바이트 응답과 84키 파싱, 정상 종료를 한 번 수행. 각 비동기 Feature 작업은 360ms 제한이며 재시도·output·저장·원시 로그 없음 | 부분 구현 | 실기에서 완료 후 장치가 계속 열거되고 연결 해제는 관찰되지 않았지만 전후 모든 상태 불변은 입증되지 않음. 모드 파라미터·시계·키맵·LCD·매크로·일반 설정은 미지원 | Q + R + U |
| 제한적 Feature 적용 | 작업별 확인 뒤 시계, 선택한 내장 모드 하나, 또는 누락 없는 84키 RGB 표만 직렬 적용. exact target/topology를 전후 확인하고 35ms pacing, bounded async operation, 필요한 ACK byte 3 검증을 사용. 시계·모드 1·모드 14·84키 RGB의 독립 실기 완료 | 부분 구현 | ACK는 결과 readback이 아니며 RGB F5도 byte-exact backup이 아님. 기본값 plan·키맵·매크로·펌웨어·부트로더 live 작업과 임의 payload는 없으며, 고정 LCD 진단은 별도 row에 제한 | W |
| 부분 transaction quarantine | F5/Feature/LCD 진단 작업의 첫 report 전에 target identity만 담은 durable marker를 atomic+fsync로 저장. report 제출 뒤 실패·cancel 미확인·postflight 실패 시 재실행 뒤에도 해당 target 작업을 차단 | 구현 | marker는 backup/rollback이 아님. cross-process lock은 KeyCanvas만 직렬화하므로 제조사 utility·Windows VM·기타 HID tool을 확인 전에 완전히 종료해야 함 | Q + W |
| quarantine 해제 | 한 process에서 Device Inspector가 target 0 collection을 관찰한 뒤 동일 identity의 정확한 4 collection 재등장을 관찰하고, 사용자가 selector를 USB 위치에 둔 채 cable을 분리해 LCD·LED·장치가 완전히 꺼진 뒤 원래 USB 위치로 재연결했음을 확인한 경우에만 staged durable clear 수행. primary에는 `[]` receipt가 남고 `.pending-clear`는 동기화 후 제거되며 load는 두 파일의 identity 합집합을 사용 | 구현 | staged 제거·directory fsync 실패 시 old identity를 복원하고 error. serial이 없으면 원래 USB location 필요. 앱 재실행·handle close·빠른 USB 재연결·2.4G/BT 전환·marker/app data 삭제는 복구가 아님 | R + 사용자 확인 |
| LCD output transport | 한 파일의 Feature 1개/Output 1개 call site에 bootstrap·qualified adapter를 제한. exact topology와 IORegistry IF3/IF2/common USB parent, one-use plan auth, page별 Output completion/expected input, no retry, postflight, durable lease·quarantine를 공통 강제. qualified encoder는 40프레임·2,592,768바이트 정책을 단일 Core API로 적용 | 실험적 부분 구현 | input에 page index가 없어 sequence는 page/flash 수락 증명이 아님. macOS는 numeric endpoint `0x03/0x84`를 직접 선택·관찰하지 않음. 중단 뒤 남은 lease는 다른 live 작업을 차단하고 retryable receipt→durable quarantine→자격 폐기로만 reconcile. 기존 실기는 evidence-only이고 새 receipt에 backfill되지 않음. fresh qualification 전에는 UI가 fail-closed하며 140프레임은 offline ceiling일 뿐 | W + U |
| 펌웨어/부트로더 | 의도적으로 없음 | 미구현 | 업데이트·추출·플래시·부트로더 진입은 프로젝트 범위 밖 | 제외 |

## 권장 우선순위

1. **P0 — 실기 의미 검증:** 단발 전송과 ACK·postflight는 확인했습니다. 이제 시계와
   조명의 육안 결과, 방향 raw 값의 의미, 전원 재연결 뒤 지속 여부를 기록합니다.
   현재 파라미터 readback이 없고 F5도 밝기 조정값이므로 자동 rollback을 주장하지
   않습니다.
2. **P1 — 로컬 편집 완성:** 구현된 GIF 탐색·편집·RGB565 파일 내보내기를 바탕으로
   undo/redo, 자산 정리, Keymap 동작 편집기, Macro 순서·지연 편집을 장치 없이
   완성합니다.
3. **P2 — 읽기 전용 진단 확장:** 공개 레지스트리 정보만으로 수신기와 hardware
   revision을 안전하게 구분할 수 있는지 조사합니다. 장치 report 읽기는 이 단계에
   자동으로 포함되지 않습니다.
4. **P3 — 검증된 장치 상태 읽기:** 키별 RGB와 같은 좁은 경로만 별도 설계 검토와
   실기 확인을 거쳐 추가할지 판단합니다. 개인 식별자와 화면/매크로 payload는
   수집하지 않습니다.
5. **P4 — 쓰기 복구 경계 검토:** 기본값 dry-run은 전체 초기화나 live restore로
   확장하지 않습니다. LCD는 고정 진단에서 시작하는 Core 영속 qualification과
   current-editor immutable 1…40프레임 exact-plan 경로를 구현했습니다. 기존 macOS
   16/16·commit·postflight·모서리 육안 확인과 USB-mode cable removal→real absence→
   same-location exact4 reappearance는 evidence일 뿐 production receipt로 backfill하지
   않습니다. 새 build에서 fresh 전체 순서를 마치기 전에는 40프레임 UI가 fail-closed
   하며, 각 qualified host 성공도 별도 육안 결과 전에는 완료로 간주하지 않습니다.
   140프레임은 계속 offline format ceiling입니다.

펌웨어 업데이트, 추출, 플래시와 부트로더 진입은 우선순위 목록에 포함하지 않으며
계속 프로젝트 범위 밖에 둡니다. 모든 단계에는
[소스·interoperability 경계](CLEAN_ROOM.md)와 [설계 및 안전 경계](DESIGN.md)가
우선 적용됩니다.

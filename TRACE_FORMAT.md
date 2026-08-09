# KeyCanvas 오프라인 trace 형식

이 형식은 사용자가 직접 선택한 정제된 JSON 파일을 오프라인에서 요약·비교하기
위한 중립적인 입력 구조입니다. KeyCanvas는 trace를 만들기 위해 장치나 공식
앱을 열거나 실시간 통신을 캡처·후킹·복호화·재생·전송하지 않습니다. 특정
키보드 명령이나 opcode의 의미도 주장하지 않습니다.

## JSON 구조

최상위 object는 `schemaVersion`, `label`, `provenance`, `events`만 가질 수
있습니다. `provenance`와 각 event도 아래에 정의된 key만 허용하며 알 수 없는
key는 오류로 처리합니다.

```json
{
  "schemaVersion": 1,
  "label": "synthetic-lighting-before",
  "provenance": {
    "origin": "synthetic",
    "authorizedUse": true,
    "identifiersRemoved": true,
    "absoluteTimestampsRemoved": true,
    "firmwareTrafficExcluded": true
  },
  "events": [
    {
      "index": 0,
      "offsetMicros": 0,
      "direction": "host-to-device",
      "transfer": "control",
      "reportID": 0,
      "bytesHex": "00112233"
    },
    {
      "index": 1,
      "offsetMicros": 2500,
      "direction": "device-to-host",
      "transfer": "interrupt",
      "reportID": 0,
      "bytesHex": "aabbccdd"
    }
  ]
}
```

예시의 값은 형식 설명을 위해 새로 만든 합성 데이터이며 실제 통신에서 가져온
바이트가 아닙니다.

## Provenance

`provenance.origin`은 다음 중 하나입니다.

- `synthetic`: 실제 캡처에서 복사하지 않고 프로젝트가 새로 만든 데이터
- `authorized-private-observation`: 권한 있는 관찰자가 적법하게 생성한 비공개
  캡처에서 최소 사실만 추출·정제해 만든 로컬 데이터

다음 Boolean은 모두 반드시 `true`여야 하며 하나라도 빠지거나 `false`이면
입력을 거부합니다.

- `authorizedUse`: 관찰 및 분석에 필요한 권한을 확인함
- `identifiersRemoved`: serial, location, 사용자·호스트·경로 등 식별자를 제거함
- `absoluteTimestampsRemoved`: 절대 시각을 제거하고 필요한 상대 시간만 남김
- `firmwareTrafficExcluded`: firmware, updater 및 bootloader traffic을 제외함

이 object는 제출자의 확인을 구조화할 뿐 진실성, 권리 또는 정제 상태를
자동으로 증명하지 않습니다. 권한 있는 비공개 관찰에서 파생된 명세나 구현에는
[클린룸 정책](CLEAN_ROOM.md)의 별도 provenance 기록과 검토도 필요합니다.

## Event 필드와 시간 규칙

- `index`: 배열 위치와 같은 0부터 시작하는 연속 정수
- `offsetMicros`: 선택적인 상대 시간. 앞쪽 event에서 생략할 수 있지만 처음
  존재하는 값은 반드시 `0`이어야 합니다. 이후 존재하는 값은 감소할 수 없고
  각각 `0...3,600,000,000`µs(최대 1시간) 범위여야 합니다. 값이 없는 event는
  시간 비교에서 건너뜁니다.
- `direction`: `host-to-device` 또는 `device-to-host`
- `transfer`: `control`, `interrupt`, `bulk` 중 하나
- `reportID`: `0...255` 범위의 정수
- `bytesHex`: separator가 없는 짝수 길이의 소문자 16진수 문자열

`label`은 trim했을 때 비어 있지 않은 UTF-8 128바이트 이하 문자열이며 제어
문자와 줄바꿈을 포함할 수 없습니다. 민감한 이름이나 식별자를 넣지 마세요.

## 입력 제한

- JSON 파일: 최대 2,097,152바이트
- event: 최대 10,000개
- event 하나의 payload: 최대 4,096바이트
- 모든 payload 합계: 최대 2,097,152바이트

decoder는 구조, provenance, 크기와 시간 제한을 분석 전에 확인합니다. 공개 trace
Core는 decode와 분석만 제공하며 trace 또는 payload를 재직렬화하는 public
encoder는 제공하지 않습니다.

## 출력

```sh
swift run keycanvas-trace summary sanitized-trace.json
swift run keycanvas-trace summary sanitized-trace.json --json
swift run keycanvas-trace diff before.json after.json
swift run keycanvas-trace diff before.json after.json --json
```

사람용·JSON 출력 모두 입력 `label`, 개별 timestamp, 최초·최종 timestamp 및
payload 값을 표시하지 않습니다. Summary는 event·방향·전송·report ID·길이
집계와 상대 duration만 제공할 수 있습니다. Diff는 추가·제거·변경 event,
metadata field, payload 길이와 달라진 byte offset만 제공합니다. Offset은 byte
위치이며 관찰된 전·후 byte 값은 포함하지 않습니다.

분석기는 입력을 업로드하거나 장치와 통신하지 않습니다. live capture, process
hook, report replay/injection, HID device I/O 또는 trace encoding API도 제공하지
않습니다.

## 원본 캡처를 공개하지 마세요

원본 캡처나 report stream에는 serial/location ID, 사용자명과 경로, 실제 키
입력·매크로·프로필명, 토큰·키, 화면·미디어 데이터, firmware 또는 bootloader
traffic이 섞일 수 있습니다.

원본 캡처는 저장소, Issue/PR, Discussion, Actions log/artifact, Release 또는
보안 신고에 첨부하지 않습니다. 공개 가능한 것은 최소 사실을 독립적으로 다시
기술한 명세와 프로젝트가 새로 작성한 합성 test data뿐입니다. 저장소는 tracked
JSON을 기본 거부하며 예외는 정확한 경로와 검토 근거를 명시해야 합니다.

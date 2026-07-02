# Codex accounts & auth (OpenAI)

**Language:** [English](../en/CODEX-AUTH.md) · 한국어

라우터가 두 개의 OpenAI Codex 신원(`personal`, `company`)을 어떻게 분리하는지, 각각에
어떻게 로그인하는지, 그리고 OpenAI의 계정 모델이 무엇을 해주고 무엇을 **해주지 않는지**
정리한다.

> 아래 내용은 **2026-07-02** 기준 OpenAI 공개 문서를 따른다. Codex CLI와 데스크톱 앱
> 모두 자동 업데이트되므로, 정확한 플래그는 *실행 시점에 직접 확인*하는 것으로 취급하라.
> 출처: [Codex auth](https://developers.openai.com/codex/auth),
> [config](https://developers.openai.com/codex/config-advanced),
> [CLI reference](https://developers.openai.com/codex/cli/reference),
> [ChatGPT account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).

## 반드시 기억해 둘 한 가지

**ChatGPT 웹의 "계정 전환"은 Codex 계정 전환이 아니다.**

- ChatGPT **웹**에서는 최대 **2개** 계정을 활성 상태로 두고 오갈 수 있다. 채팅, 메모리,
  결제, 워크스페이스는 계정별로 분리된다.
- OpenAI는 이 기능이 **웹 전용**이라고 밝히고 있다. Codex 데스크톱 앱이나 네이티브 ChatGPT
  모바일 앱에서는 **지원되지 않는다**.

그래서 브라우저에서 계정을 바꿔도 Codex에는 아무 영향이 없다. Codex는 자신의 신원을
**`CODEX_HOME`**에서 읽어온다. 이는 상태를 담는 디렉터리로 `config.toml`, `auth.json`,
`history.jsonl`, 로그가 들어 있다. 라우터는 계정마다 별도의 `CODEX_HOME`을 주고 그것을
바라보게 하여 Codex를 실행한다:

```
ai codex personal      # CODEX_HOME=~/.codex-personal
ai codex company        # CODEX_HOME=~/.codex-company
ai codex company --account personal   # personal 신원, company 워크스페이스
```

바로 그 프로세스 수준의 디렉터리 격리가 계정 분리 그 자체다. CLI에서도 똑같이 동작한다.
(데스크톱 앱과 CLI는 같은 에이전트/설정을 공유하지만 번들된 버전이 다를 수 있다. 앱은
현재 실행마다 임의의 `CODEX_HOME`을 지정하는 방식을 받아들이지 않으므로, 라우터는
**CLI 우선**이다. [지원하지 않는 것](#지원하지-않는-것)을 참고하라.)

## 프로필별 인증 방식

Codex는 로그인 정보를 로컬에 캐시하며 자격 증명을 세 가지 방식으로 저장할 수 있다.
라우터가 대신 골라주지는 않는다. 각 루트가 어떤 방식을 쓰는지 **알려줄** 뿐이며(`ai doctor`),
토큰의 실제 내용은 절대 읽지 않는다.

| 방식 | 자격 증명이 저장되는 곳 | 선택 방법 | 라우터 격리 수준 |
|------|------------------|---------------|------------------|
| **File** (기본) | `$CODEX_HOME/auth.json` (평문 — 비밀번호처럼 다뤄라) | 기본값, 또는 `config.toml`에 `cli_auth_credentials_store = "file"` | **완전** — 계정마다 `auth.json`이 각자의 루트 아래에 있다 |
| **Keyring** | OS 자격 증명 저장소 | `cli_auth_credentials_store = "keyring"` | 부분 — `CODEX_HOME`이 설정과 히스토리는 격리하지만 OS 키링 항목은 **공유될 수 있다**. 활성 계정은 `ai codex <acct> -- login status`로 확인하라 |
| **API key** | `auth.json` (`--with-api-key`로 저장) | 아래 참고 | 완전 (파일 기반) |
| **Auto** | 파일 또는 키링, 도구가 선택 | `cli_auth_credentials_store = "auto"` | `auth.json`이 있으면 파일로, 없으면 키링으로 취급 |

**확실하고 검증 가능한 격리를 원한다면 파일 기반을 택하라**(이 머신에서는 그것이 기본값).
`keyring`으로 설정하면 격리 여부가 OS 키링이 `CODEX_HOME`별로 항목을 구분하느냐에 달리는데,
이는 보장되지 않는다. `ai doctor`가 이 점을 표시해 주니 세션 안에서 직접 확인하라.

## 각 프로필에 로그인하기

`--` 뒤에 오는 것은 전부 실제 `codex`로 그대로 전달되며, 알맞은 `CODEX_HOME` 아래에서
실행된다:

```sh
# 구독 / ChatGPT 로그인 (가장 흔함)
ai codex personal -- login
ai codex company  -- login
ai codex company  -- login --device-auth     # 헤드리스 / 원격 머신

# API 키 기반 프로필 (CLI/IDE. ChatGPT 로그인이 필요한 Codex cloud에는 쓸 수 없음)
printenv OPENAI_API_KEY | ai codex company -- login --with-api-key

# 액세스 토큰 기반
printenv CODEX_ACCESS_TOKEN | ai codex company -- login --with-access-token

# 토큰을 노출하지 않고 상태 확인 (언제든 안전하게 실행 가능)
ai codex personal -- login status
ai doctor                                     # 계정별 방식 + 격리 요약
```

라우터는 여러분의 키를 인자로 받거나, 출력하거나, 트랜스크립트에 기록하는 일이 **결코**
없다. 위에서 보인 대로 비밀 값은 곧장 `codex`로 파이프하라. 그러면 라우터를 거치지 않는다.
어떤 관리자 통제, 데이터 보존, 데이터 소재지(residency), RBAC, 결제가 적용되는지는
인증 방식에 따라 달라진다. 그건 여러분과 OpenAI 사이의 문제이며, 라우터는 *어느* 신원이
활성인지만 고정한다.

## 라우터가 막아주는 함정들

- **루트 사이에서 `auth.json`을 복사하지 마라.** 리프레시 토큰은 일회용이라 복사한 파일은
  금세 만료되어 조용히 망가진다. `ai doctor`가 두 파일의 지문을 떠서 서로 같으면 경고한다.
  두 번째 계정을 준비하려면 새로 `login`을 실행하라. `cp`로 복사하지 **마라**.
- **CLI와 IDE 확장은 캐시된 로그인을 공유한다.** 한쪽에서 로그아웃하면 다음번에 다른 쪽에서
  다시 로그인해야 할 수 있다. 이는 OpenAI의 정상 동작이지 라우터의 버그가 아니다.
- **`--profile`은 설정 프로필이지 계정이 아니다.** `codex --profile foo`는
  `$CODEX_HOME/foo.config.toml`의 설정 블록을 고를 뿐, 인증을 격리하지 **않는다**. 계정
  격리는 `CODEX_HOME`이 담당한다(라우터가 고정하는 대상). 또한 프로젝트 수준의
  `.codex/config.toml`은 인증/프로바이더에 민감한 키(`openai_base_url`,
  `chatgpt_base_url`, `model_provider(s)`, `profile(s)`)를 재정의할 수 없도록 설계돼 있다.
- **`auth.json` 권한.** 이 파일은 비밀번호나 마찬가지다. `ai doctor`는 권한이
  `600`/`400`이 아니면 경고하고, 바로잡을 정확한 `chmod` 명령을 출력한다.

## 지원하지 않는 것

라우터를 정확하고 자격 증명 측면에서 안전하게 유지하기 위해 의도적으로 범위에서 뺀 것들:

- **Codex용 데스크톱 앱 계정 격리.** 라우터는 CLI 우선이다. `Codex.app`이 실행마다
  `CODEX_HOME`을 존중하도록 만들려고 시도하지 않는다. 여러 계정을 쓰는 Codex는 CLI에서
  다뤄라. (Claude의 경우 데스크톱 앱은 `--user-data-dir`로 격리되지만, Codex에는 여기서
  검증된 동등한 경로가 없다.)
- **ChatGPT 웹 쿠키/세션 하이재킹.** 브라우저 쿠키를 조작하지 않는다. 웹 계정 전환은
  브라우저 안에 머무는 일이며 Codex와는 무관하다.
- 원본 `auth.json`, 액세스/리프레시 토큰, API 키, 쿠키, 브라우저 세션 데이터를
  **읽거나, 출력하거나, 복사하거나, 커밋하거나, 로깅하는 일**. `ai doctor`가 읽는 것은 파일의
  *존재 여부*, *방식*, 되돌릴 수 없는 *지문*, 그리고 *설정 키 이름* 하나뿐이다.
- **OS 키링 관리.** 키링 방식을 택하면 격리 보장은 OS의 몫이다. 라우터는 그 한계를 덮어
  가리지 않고 있는 그대로 알려준다.
- **Codex cloud / Remote Control 프로비저닝.** Codex cloud는 ChatGPT 로그인과 로그인된
  호스트를 요구한다. 라우터는 로컬 신원만 고정할 뿐 원격 호스트를 조율하지 않는다(그 향후
  작업은 [ORCHESTRATION-PLAN.md](ORCHESTRATION-PLAN.md)를 참고하라).

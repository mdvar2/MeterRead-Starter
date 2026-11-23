# Progress

Fill this in before you hand in. Saying what's unfinished is never sent back.

## What works

All four CI steps pass locally: format, build_runner, `dart analyze --fatal-infos`, and `flutter test` (55 tests).

- **Round 1, Errors.** `lib/core/failure.dart` has a sealed `Failure`: `NoSignal`, `FieldErrors` (with the API's `errors`), `SignedOutFailure`, `NotFound` and `ServerFault` (with the `traceId` as its reference). `failureFrom` in `lib/core/network/failure_from.dart` is the only code that knows about Dio. It also unwraps a `ParallelWaitError`, from a list wait or a record wait. Both repositories and `AuthApi` throw only `Failure`s, through `guarded`. `appRetryPolicy` retries only `NoSignal`. Each screen shows failures through `FailureView` or `failureMessage`, with a reference for the server's fault and "Try again". Sign-in says "That email and password don't match.". Tested: the mapping as a table, the retry policy, and the harness cases for M-9999, M-1012 (both within 0.5 s), no signal followed by Try again, and a wrong password.
- **Round 2, The session.** The refresh token lives in `SecureTokenStore` (flutter_secure_storage). The access token stays in memory. `shared_preferences` is gone from `pubspec.yaml`. `SessionInterceptor` is a `QueuedInterceptor`: it compares the token the failed request carried with the current one and refreshes only when they match. Only a refusal (401 or 400) ends the session. No signal, or a 500 on refresh, leaves the reader signed in. That holds at launch too: a stored session with no signal goes to `SignedIn(null)` and keeps the token. Tested through the harness (Expire access tokens, then M-1002, `refreshCalls` +1) and with unit tests on the interceptor (three requests, one refresh; no signal on refresh; a refused refresh).
- **Round 3, Offline.** The round screen shows what `RoundDao` holds straight away. `roundSyncProvider` fetches every page in the background and saves the result. The header always shows "Last updated HH:mm." When the last fetch failed it shows "No signal. Last updated HH:mm." (or "Couldn't update the round. …") with Try again. Pull to refresh works. The outbox makes the `Idempotency-Key` in `capture`, when the reader taps Save, stores it with the reading, and `send` always reuses it. `AppDatabase.wipe()` runs on sign-in, sign-out and a session the API ends, and the token is deleted on sign-out and on an ended session. Tested: no signal plus pull-down keeps all 14 meters under the banner; the M-1007 lost answer is stored once and ends up Read, never Query; sign-out with a reading waiting leaves 0 rows and no token; a session the API ends leaves 0 rows; signing in as a second reader shows none of the first reader's round.
- **Round 4, Forms, lists and words.** Every page of the round is fetched (14 meters, down to 21 Umthombo Road). The reading field is labelled "Reading in kWh". The phone checks it ("Enter the reading.", "Use digits only, like 48 590.") and parses digits and spaces to an `int`, never a `double`. The server's field error shows under the field with the typed text kept. `metersLeft` is one ICU plural in `app_en.arb` and `app_zu.arb`. Each meter's status is in words on its round row, and the icon is excluded from semantics. Send now and Discard are labelled buttons. Tested: the plural in English and isiZulu ("Kusele imitha engu-0" with `roundDone: true`), every form case on 2 Lwandle Street, the field's semantics label, and `androidTapTargetGuideline` plus `labeledTapTargetGuideline` on the meter screen with a reading waiting and on the round.
- **Stretch A.** With readings waiting, sign-out asks first, using an ICU plural ("1 reading hasn't been sent…"), and Cancel keeps the reader signed in.
- **Stretch B.** `textScale: 2` tests cover the round, the meter screen with a reading waiting, and a refusal. Nothing overflows.
- **Stretch C.** A round row whose meter has a reading waiting says "Not sent yet", and stops when the reading goes.

## What doesn't work yet

- I checked everything through the harness and the tests only. I haven't walked the brief's "Done when" steps by hand on the emulator.
- The meter screen needs signal. Only the round is cached, so with no signal a meter says "No signal…" until it's back. Readings saved while offline wait in the outbox.
- The server's field errors (such as "That's lower than the last reading…") are shown as the API sends them, in English, even in isiZulu.
- The isiZulu ARB only has the translator's `metersLeft` draft. Every other new message falls back to English.
- A launch with no signal sets `SignedIn(null)`, so the reader's name is unknown until a request gets through. Nothing shows the name today.
- Readings waiting in the outbox aren't sent automatically when the signal comes back. The reader taps "Send now".

## What I copied, and what I changed

| File in MeterRead | Copied from (Matric Compass, RondiTrack or class materials) | What I changed |
| --- | --- | --- |
| (none) | Nothing copied: written fresh against this API, as a revision run after the session. | Patterns follow Week 11 Days 1–4. |

## What the phone keeps

Everything MeterRead stores on the phone, where, and what removes it:

| What | Where | Removed when |
| --- | --- | --- |
| Refresh token | flutter_secure_storage (Keystore / Keychain), via `SecureTokenStore` | Sign-out; the API refusing a refresh (session ended); replaced on every refresh |
| Access token | Memory only (`accessTokenProvider`) | Sign-out, session ended, app closed; replaced on every refresh |
| Today's round (header with `metersLeft` and `fetchedAt`, meters in walking order, statuses) | Drift: `cached_rounds`, `cached_meters` | Replaced on every successful fetch; wiped on sign-in, sign-out and session ended |
| Readings not yet accepted, with their one Idempotency-Key and last error | Drift: `pending_readings` (the outbox) | When the server accepts or refuses it; Discard; wiped on sign-in, sign-out and session ended |

## What I'd do next

- Send the outbox automatically when the signal returns, or when the round refreshes successfully.
- Cache each meter's detail so the meter screen also works without signal.
- Map the server's field errors to localised messages, and get the isiZulu drafts reviewed by a first-language speaker.
- Walk the "Done when" steps by hand on the emulator.

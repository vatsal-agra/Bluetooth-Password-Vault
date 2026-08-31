# BPV-1 — Embedded Bluetooth Password Vault with Secure Credential Storage

**Firmware simulator — single-file, offline, real cryptography.**

| | |
|---|---|
| Archit Arora | 24BYB1144 |
| Amol Bhatia | 24BYB1026 |
| Siddhant Dhale | 24BAI1185 |
| Vatsal Agrawal | 24BAI1355 |

---

## 1. What this is

The hardware project is a portable ESP32 device — an OLED display, a rotary encoder and a
battery in a small enclosure — that stores AES-encrypted credentials in flash, unlocks with a
master password, and then types the selected credential into a paired computer over Bluetooth,
appearing to that computer as an ordinary wireless keyboard.

The board is not built yet. `index.html` is the **firmware simulator**: the state machine, the
storage format, the display driver, the HID transport and **all of the cryptography** are the
real thing, running in a browser. Only the silicon and the radio are emulated. It is built to be
projected on a screen and walked through by a reviewer.

Nothing is faked for the demo:

* Keys really are derived with **PBKDF2-HMAC-SHA256 → HKDF-SHA256** through `window.crypto.subtle`.
* Credentials really are sealed with **AES-256-GCM** and a fresh 96-bit nonce per record.
* The "flash" really persists across reloads, and the failed-attempt counter really cannot be
  rewound by reloading the page.
* Corrupting a byte of ciphertext really does make the GCM tag check fail.

## 2. Running it

Double-click **`index.html`**. That is the whole procedure — no build step, no server, no
npm, no CDN, no network access of any kind. Chrome and Firefox both treat `file://` as a
secure context, so `window.crypto.subtle` is available.

If a browser ever refuses to expose `crypto.subtle`, the page says so on screen instead of
failing silently, and you can fall back to a local server:

```bash
python -m http.server 8000
```

`serve.bat` (Windows) and `serve.sh` (macOS/Linux) do exactly that and open the page for you.

> Keep the tab in the **foreground** during the demo. Browsers throttle timers in background
> tabs to one tick per second, which makes the simulated keystroke timing crawl.

### Hosted version

The same file is deployed on Netlify straight from this repository — no build step, publish
directory `.`. `netlify.toml` sets a Content-Security-Policy that makes the offline claim
enforceable rather than merely stated:

```
default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline';
img-src 'self' data:; connect-src 'none'; base-uri 'none'; form-action 'none';
frame-ancestors 'none'
```

`connect-src 'none'` and `default-src 'none'` mean the browser itself would block any fetch,
XHR, WebSocket, font, frame or external script the page tried to make. It loads and runs
identically — the self-test suite passes 19/19 under that policy — because there is nothing to
block. Open DevTools during the demo and the network tab shows exactly one request: the
document itself.

## 3. Two-minute walkthrough

Press **▶ Play full walkthrough** in the *Guided demo* card. It drives the complete specified
algorithm on its own, with a caption bar explaining each step. `DEMO_SCRIPT.md` has the
manual version, with the lines to say and the questions to expect.

The default master password is **`Vault@2026`** (shown in the *Demo cheat sheet* card).
On a fresh machine the device boots unprovisioned and asks you to set one on the OLED;
*Quick factory provision* skips that and seeds five demo credentials.

**Controls.** Rotate the encoder with the mouse wheel over the knob, the CW/CCW buttons, or
<kbd>↑</kbd>/<kbd>↓</kbd>. Press with **PRESS**, <kbd>Enter</kbd> or <kbd>Space</kbd>. Long-press
(back / submit) with **HOLD** or <kbd>Esc</kbd>. During password entry you can also just type on
the keyboard; <kbd>Enter</kbd> submits.

## 4. The operational algorithm

Implemented in this exact order — see `attemptUnlock()`, `decryptRecord()` and
`sendCredential()` in the source.

1. **Boot.** Initialise the simulated I²C bus, SSD1306 panel, NVS partition, hardware RNG,
   crypto backend and BLE stack, with a scrolling boot log and a team splash screen.
2. **Prompt for the master password** on the OLED, entered with the rotary encoder through a
   character ring (`DEL` and `OK` are ring entries), or typed directly.
3. **Hash and verify**: derive the root key from the entry and compare the derived verifier
   against the stored one in constant time.
4. **On failure**: increment a **persisted** attempt counter and return to the prompt. After
   5 failures the device enters an escalating cooldown (15 s → 30 s → 60 s → 120 s → 300 s →
   600 s → 900 s) stored as an absolute deadline, so it survives reboots.
5. **On success**: derive the vault key, reset the counter, and show the stored account list.
6. **The user selects a credential** with the encoder.
7. **Decrypt** that record with AES-256-GCM; the 128-bit tag is verified before anything is used.
8. **Verify or establish the Bluetooth HID connection** (advertise, connect, bond, register the
   HID report map).
9. **Transmit** username → <kbd>Tab</kbd> → password → optionally <kbd>Enter</kbd>, as individual
   8-byte HID keyboard reports.
10. **Zeroize** the decrypted credential in RAM — a random pass, then a zero pass.
11. **Return to the menu**, and auto-lock after the configurable inactivity timeout, which
    zeroizes the vault key as well.

## 5. Cryptographic design

```
master password  +  16-byte salt from the hardware RNG
        |
        v   PBKDF2-HMAC-SHA256, 150 000 iterations (configurable 50k … 600k)
   root key (256 bit)                          <-- never stored, never leaves RAM
        |
        +-- HKDF-SHA256(info = "bpv/verifier/v1")   -> verifier  (32 B)  STORED IN FLASH
        \-- HKDF-SHA256(info = "bpv/vault-aes/v1")  -> AES-256 key      RAM ONLY
                 |
                 v   AES-256-GCM,  IV = 12 random bytes per record,
                     AAD = "v1|<record id>|<label>",  128-bit tag
            sealed credential blob { username, password, url }
```

**The vault key is derived, never stored.** Flash contains only the salt, the KDF parameters,
the verifier, and per-record IV + ciphertext + tag. Because the verifier and the vault key are
two different HKDF branches of the same root, an attacker who reads the verifier out of flash
learns nothing usable about the AES key — it is a one-way function of the root in a different
domain.

Per-record detail:

* **Fresh nonce per encryption.** A 96-bit nonce from `crypto.getRandomValues()` for every
  record and every re-encryption. Nonce reuse under one key is the classic way to destroy GCM,
  so the self-test suite asserts uniqueness across 200 encryptions.
* **Associated data binds the record.** The record id and label are authenticated but not
  encrypted, so relabelling a record in flash, or moving one record's ciphertext onto another
  record, is detected by the tag check.
* **Non-extractable key handle.** The AES key is imported with `extractable: false`, mirroring a
  hardware key slot; the UI only ever shows a SHA-256 fingerprint of it.

### Why the attempt counter is written *before* verification

This is deliberate, and it is the single most important defensive decision in the design.

The naive implementation checks the password first and records the failure afterwards. That
loses to the simplest hardware attack there is: guess, and cut the power the moment the guess is
rejected. The counter never reaches flash, and the attacker gets unlimited attempts against a
device sitting on their bench.

BPV-1 therefore **commits the incremented counter to NVS before the PBKDF2 derivation even
starts**. A power cut during verification can only ever lose the *reset* that follows a
successful unlock — which fails safe, because the worst case is one spurious recorded failure.

You can prove it during the demo: run *Power-cycle to reset the attempt counter* in the Attack
Lab, or simply reload the page mid-attack. The counter comes back exactly where it was. The
serial log prints the moment it happens:

```
S sec: attempt #3 counter committed to NVS BEFORE verification
       (anti-tamper: power-cycling cannot rewind it)
```

### Other countermeasures

* **Constant-time verifier comparison** (`ctEqual`, XOR accumulator, no early exit) plus a
  260 ms floor on the response time, so a wrong password cannot be distinguished by timing.
* **Panic wipe** after 15 lifetime failures (configurable) destroys the salt and the verifier,
  which makes every stored ciphertext permanently unrecoverable.
* **Two-pass zeroization** — random, then `0x00` — of the vault key, the root key and every
  decrypted credential, on hide, on lock, on auto-lock and after every transmission.
* **Explicit physical confirmation** before any keystroke is transmitted, so a compromised host
  cannot silently ask the device for credentials.
* **Link-layer encryption** (LE Secure Connections / AES-CCM) on the Bluetooth link, with a
  toggle so the demo can show what a sniffer sees with it on and off.

### Accepted trade-offs

These are deliberate, and worth stating before a reviewer asks.

* **Record labels are plaintext metadata.** The menu can then be drawn without decrypting
  anything. An attacker with the chip learns *which* accounts exist, not their contents.
  Encrypting the index as one blob would remove the leak at the cost of decrypting everything at
  unlock. The labels are still authenticated through the AAD, so they cannot be modified.
* **The host is trusted after transmission.** Once the credential arrives as keyboard input, a
  keylogger on the host defeats any hardware vault. The device guarantees confidentiality only
  up to the HID boundary.
* **JavaScript strings cannot be wiped.** The simulator zeroizes every `Uint8Array` it controls
  and models the rest honestly; real firmware wipes each `char` buffer with
  `mbedtls_platform_zeroize()`.

## 6. The interface

| Panel | What it shows |
|---|---|
| **Device** | The simulated board: a 128×64 monochrome OLED rendered pixel by pixel from a real 1-bit framebuffer, the EC11 rotary encoder, power/BLE/activity LEDs, and the front-panel buttons. |
| **Paired host** | A mock login form on "DESKTOP-PC". Keystrokes arrive here exactly as the device sends them, including the Tab that moves focus and the Enter that submits. |
| **BLE sniffer** | Over-the-air capture. With LE Secure Connections on you see opaque AES-CCM payloads; switch it off and every keystroke becomes readable. |
| **USB provisioning console** | The serial enrolment tool. Adds records (encrypted on the device, never by the host), deletes them, and re-keys the whole vault under a new master password. |
| **Attack lab** | Nine executable attacks against the live vault — see below. |
| **Serial monitor** | ESP-IDF-style log with uptime, level and tag. Security-relevant lines are highlighted. |
| **Flash (NVS)** | Colour-coded hex dump of a synthesised raw flash image, plus a scanner that searches every byte for known plaintext secrets. |
| **Crypto trace** | Every PBKDF2, HKDF and AES-GCM operation with its parameters, truncated values and measured duration. |
| **SRAM** | The volatile working set: which secret regions are resident, and which have been zeroized. Reveal the bytes with a checkbox. |
| **State machine** | All 16 firmware states with the current one highlighted, and a transition log. |
| **Self-test** | 19 assertions including cryptographic known-answer tests. |
| **About / docs** | The design, in the page itself, so the reviewer never has to leave the screen. |

## 7. Attack lab

Every entry runs against the real vault and prints a verdict.

| Attack | Result |
|---|---|
| Desolder the flash and dump the NVS partition | **Blocked** — ciphertext only; no key, no plaintext |
| Brute-force the master password | **Blocked** — persisted counter, escalating lockout, one full PBKDF2 per guess |
| Power-cycle to reset the attempt counter | **Blocked** — the counter is committed before verification |
| Flip one bit in a stored ciphertext | **Blocked** — GCM tag verification fails |
| Swap two records in flash | **Blocked** — AAD binds ciphertext to record id and label |
| Rename a label in flash | **Blocked** — the label is authenticated |
| Sniff the Bluetooth link | **Leaks with link encryption off** — the honest answer; with LE Secure Connections on, the capture is opaque |
| Scrape the vault key out of RAM | **Partial leak while unlocked** — also the honest answer; the key must exist to decrypt. Mitigated by short auto-lock and zeroization, and blocked entirely once locked |
| Restore the vault | Undoes the tampering so the demo can continue |

The two entries that leak are there on purpose. A threat model that claims everything is
blocked is not a threat model.

## 8. Self-test suite

Press **Run self-test suite**. 19 assertions, roughly 50 ms:

* SHA-256 known-answer test (`"abc"`).
* PBKDF2-HMAC-SHA256 known-answer tests at c=1 and c=4096 against published vectors.
* HKDF determinism, and domain separation between the verifier and the vault key.
* AES-256-GCM round trip; rejection of a flipped bit, of the wrong key, and of modified AAD.
* IV uniqueness across 200 encryptions.
* Constant-time comparison correctness.
* base64 and hex codec round trips.
* `SecureBuffer` zeroization leaves no residual byte.
* The attempt counter survives a simulated power cut.
* **The vault key does not appear anywhere in the flash image** (searched byte by byte).
* Every character in the seeded credentials has a HID usage code.
* The lockout ladder is monotonically increasing, and record IVs are distinct.

A headless harness was also used during development to drive the whole flow outside a browser —
provision, wrong password, persisted counter, lockout escalation, unlock, decrypt, transmit,
zeroize, tamper detection and lock — 24 further assertions, all passing.

## 9. Mapping to the real hardware

| Simulator | ESP-IDF / Arduino equivalent |
|---|---|
| `crypto.subtle` PBKDF2 | `mbedtls_pkcs5_pbkdf2_hmac()` with `MBEDTLS_MD_SHA256` |
| `crypto.subtle` HKDF | `mbedtls_hkdf()` |
| `crypto.subtle` AES-GCM | `mbedtls_gcm_crypt_and_tag()` / `esp_aes_gcm` (hardware accelerated) |
| `crypto.getRandomValues()` | `esp_random()` / `esp_fill_random()`, RF-noise seeded TRNG |
| `localStorage` image | `nvs_flash` + `nvs_set_blob()` on the `nvs` partition |
| 128×64 canvas framebuffer | `Adafruit_SSD1306` / `u8g2` over I²C at `0x3C` |
| Rotate / press / long-press | EC11 encoder on GPIO 32/33 + switch on GPIO 25, PCNT unit and ISR |
| Simulated BLE HID | `esp_hidd_profile` / NimBLE HID-over-GATT, appearance `0x03C1` |
| `SecureBuffer.zeroize()` | `mbedtls_platform_zeroize()` |
| — | Flash encryption, Secure Boot v2 and an eFuse-burned HMAC key in a production build |

**PBKDF2 cost on the real target.** An ESP32 at 240 MHz manages roughly 8–12 k
PBKDF2-HMAC-SHA256 iterations per second in software, so 150 000 iterations would take on the
order of 15 s — too slow for a device you unlock several times a day. A shipping build would
either use the SHA hardware accelerator, drop to ~20 000 iterations, or move to a
memory-hard KDF. The simulator exposes the iteration count as a setting precisely so this
trade-off can be shown and discussed rather than hidden.

**Bill of materials.** ESP32-WROOM-32 dev board · 0.96" SSD1306 I²C OLED · EC11 rotary encoder
with push switch · 3.7 V 500 mAh Li-Po with a TP4056 charger · slide switch · piezo buzzer ·
3D-printed enclosure.

## 10. Files

```
index.html      the entire simulator - HTML, CSS and JavaScript in one file
README.md       this document
DEMO_SCRIPT.md  the walkthrough to present, with expected questions
netlify.toml    deployment config: no build, security headers
preview.png     Open Graph card for link previews
serve.bat       backup launcher (Windows)
serve.sh        backup launcher (macOS / Linux)
```

`index.html` is self-contained by design: one plain non-module `<script>` tag, vanilla
JavaScript, no imports, no frameworks, no external assets, no network requests. Everything —
including the fallback message shown if `crypto.subtle` is missing — lives in that one file.

## 11. Driving it from the console

The firmware exposes a handle for anyone who wants to poke at it directly:

```js
await BPV.attemptUnlock('Vault@2026')   // full derive + verify path
await BPV.decryptRecord(0)              // AES-256-GCM, tag checked
BPV.buildFlashImage().bytes.length      // size of the raw flash image
BPV.NVS.data.sec                        // the persisted security block
await BPV.runTests()                    // the self-test suite
BPV.lockNow('manual')                   // zeroize everything
```

## 12. Known limitations

* Bluetooth, flash timing and power behaviour are modelled, not emulated at register level.
* JavaScript strings are immutable, so the plaintext credential exists briefly in a string that
  cannot be wiped; the byte buffers it came from are zeroized. Real firmware wipes both.
* `localStorage` is per-origin, so the "flash" is shared by any page served from the same
  origin, and browsers in private mode may block it — the page detects this and shows a
  `FLASH VOLATILE` chip instead of failing.
* The simulated PBKDF2 cost reflects the host CPU, not an ESP32; see §9.

# BPV-1 — demo script

For the review. Total runtime about six minutes, or ninety seconds if you only have that.

## Before you start

1. Open `index.html` (double-click). Keep the tab **in the foreground** — background tabs get
   their timers throttled and the keystroke animation will crawl.
2. If the vault is already provisioned from an earlier run, click **Factory wipe** first so the
   reviewer sees the first-run flow. Otherwise click **Quick factory provision**.
3. Set *Auto-lock timeout* to **5 min** if you expect to talk for a while between steps — or
   leave it at 60 s if you want the auto-lock to fire on its own, which is a good moment.
4. Master password: **`Vault@2026`**.

**Emergency fallback:** if anything goes wrong on stage, press **▶ Play full walkthrough**.
It drives the entire algorithm by itself with captions, and needs no input from you.

---

## The ninety-second version

Press **▶ Play full walkthrough** and narrate over it. It covers boot, a failed attempt, the
persisted counter, a power cut, unlock, selection, AES-GCM decryption, the Bluetooth
transmission, zeroization and auto-lock — in that order, with a caption for each step.

---

## The full version

### 1 · Boot (20 s)

Click **RESET**.

> "This is the firmware booting. I²C bus, the SSD1306 panel, the NVS flash partition, the
> hardware RNG, the crypto backend, then the BLE stack — the same order the real firmware
> brings up its peripherals. That's our team on the splash screen."

Point at the **Serial monitor** — it is a real ESP-IDF-style log with uptime, level and tag.

### 2 · A wrong password first (40 s)

Type `hunter2` on the keyboard, press <kbd>Enter</kbd>.

> "Wrong password. Now watch the security log."

Point at the line:

```
S sec: attempt #1 counter committed to NVS BEFORE verification
       (anti-tamper: power-cycling cannot rewind it)
```

> "This is the design decision I most want to talk about. Most implementations check the
> password and *then* record the failure. If you do that, the attack is trivial: guess, and cut
> the power the instant it's rejected. The counter never reaches flash and you get unlimited
> attempts. So we increment and commit the counter *before* the key derivation even starts.
> The only thing a power cut can lose is the reset after a *successful* unlock, which fails safe."

### 3 · Prove it (30 s)

**Reload the page** (F5). Look at the *Demo cheat sheet*: failed attempts is still 1.

> "Reloading the page is a power cut. The counter came back."

Or run **Power-cycle to reset the attempt counter** in the Attack Lab, which does it and prints
the before/after values.

### 4 · Lockout (30 s, optional)

Attack Lab → **Brute-force the master password / Run 5**.

> "Five guesses, then an escalating cooldown: 15 seconds, 30, 60, two minutes, five, ten,
> fifteen. It's stored as an absolute deadline, so rebooting doesn't clear it. And every guess
> costs a full PBKDF2 derivation — 150 000 iterations of HMAC-SHA256 — so an offline attack on
> the flash contents is expensive per guess, by construction."

Set the lockout aside with **Factory wipe → Quick factory provision** if you need to move on.

### 5 · Unlock (40 s)

Open the **Crypto trace** tab, then type `Vault@2026` and press <kbd>Enter</kbd>.

> "PBKDF2-HMAC-SHA256, 150 000 iterations, over the master password and a 16-byte random salt.
> That gives a root key. HKDF then splits the root into two independent keys: a verifier, which
> is the only thing we store, and the AES-256 vault key, which never touches flash. Different
> HKDF info strings, so reading the verifier out of the chip tells you nothing about the AES key."

Open the **SRAM** tab.

> "The vault key exists here, in volatile memory, and nowhere else."

### 6 · Prove there is no plaintext in flash (40 s)

Open the **Flash (NVS)** tab.

> "This is the raw partition, as a chip-off attacker would read it. Cyan is the KDF salt, amber
> is the verifier, red is the attempt counter, green are the record labels, pink are the nonces,
> orange is AES-GCM ciphertext and tag."

Click **scan for plaintext secrets**.

> "That decrypts every record in RAM and then searches the whole flash image, byte by byte, for
> those exact plaintexts. Zero matches."

If asked about the green labels — say it before they do:

> "Labels are deliberately plaintext so the menu can be drawn without decrypting anything. An
> attacker learns which accounts exist, not what they are. They're still authenticated — I'll
> show that in a moment."

### 7 · Select and transmit (60 s)

Rotate to **GitHub**, press. Press again on *SEND TO PC*.

> "It asks for a physical button press before it will type anything. A compromised computer
> can't ask the device for credentials on its own."

Confirm **YES**. Watch the host panel.

> "AES-256-GCM decryption, tag verified first. Then the Bluetooth link — advertise, connect,
> bond, register the HID report map. Then it types: username, Tab, password, Enter. To that
> computer this is just a keyboard. Fifty-two HID reports, two per keystroke."

Point at the **BLE sniffer**.

> "Over the air it's AES-CCM under LE Secure Connections. Untick the box and re-send if you want
> to see what a sniffer gets without link encryption — every keystroke, in the clear."

### 8 · Zeroization (20 s)

Open the **SRAM** tab.

> "The decrypted credential was overwritten the moment transmission finished — a random pass,
> then a zero pass. The vault key stays until the device locks."

Click **LOCK NOW**, refresh the SRAM tab.

> "Now everything is gone. The ciphertext is still on flash; nothing that can open it is."

Leave it idle for 60 s instead, and the auto-lock does the same thing on its own.

### 9 · Tamper detection (40 s)

Attack Lab → **Flip one bit in a stored ciphertext**, then unlock and open record 1.

> "One bit. The GCM tag check fails and the device refuses the record rather than emitting
> garbage into your login form."

Then **Rename a label in flash**.

> "The label is in the AES-GCM associated data. Editing it in flash breaks authentication too —
> that's what stops an attacker moving your bank ciphertext onto a label you'll click."

Click **Restore the vault** to undo both.

### 10 · Close (20 s)

Open the **Self-test** tab, click **Run self-test suite**.

> "Nineteen assertions including published known-answer vectors for SHA-256 and PBKDF2, GCM
> rejection of a flipped bit, of the wrong key and of modified associated data, nonce uniqueness
> over two hundred encryptions, and a byte-by-byte check that the vault key never appears in the
> flash image."

---

## Questions to expect

**"Is the crypto real, or simulated?"**
Real. `window.crypto.subtle` — the browser's own implementation. The self-test tab runs published
known-answer vectors against it. Nothing is stubbed.

**"Why PBKDF2 and not bcrypt/scrypt/Argon2?"**
PBKDF2-HMAC-SHA256 is what mbedTLS gives us on the ESP32 without pulling in a memory-hard KDF,
and it is what the Web Crypto API exposes natively, so the simulator and the firmware use the
same primitive. Argon2id would be the better choice against GPU attackers; on 520 KB of SRAM it
is a real constraint, which is why the iteration count is a visible setting.

**"150 000 iterations on an ESP32?"**
No — that would take about 15 seconds in software at 240 MHz. A shipping build uses the SHA
accelerator or drops to roughly 20 000. The setting is exposed so the trade-off is explicit
rather than hidden.

**"What if someone steals the device?"**
They get ciphertext, a salt, a verifier and an attempt counter. Online guessing hits the
escalating lockout and the panic wipe at 15 failures. Offline attack on the dump costs a full
PBKDF2 derivation per guess. The security reduces to the strength of the master password.

**"What if the computer is already compromised?"**
Then you lose, and no hardware vault helps. Once a credential is keyboard input, a keylogger
sees it. We guarantee confidentiality up to the HID boundary and we say so.

**"Why is the vault key in RAM at all?"**
Because it has to be to decrypt anything. We minimise the window: short auto-lock, two-pass
zeroization on every exit path, a non-extractable key handle, and nothing written to flash.
The Attack Lab's memory-scrape entry reports this as a partial leak rather than pretending
otherwise.

**"What's left to do on the hardware?"**
Assemble the board, port the state machine to ESP-IDF, and enable Flash Encryption and Secure
Boot v2 with the key in eFuse — without those, an attacker with the chip can rewrite the
firmware, and no amount of application-level crypto survives that.

# BPV-1 — hardware build

Parts list and build notes for turning the simulator into the real device.

*Archit Arora (24BYB1144) · Amol Bhatia (24BYB1026) · Siddhant Dhale (24BAI1185) · Vatsal Agrawal (24BAI1355)*

---

## 0. The decision that matters most

**Buy a board with the original ESP32 chip (ESP32-WROOM-32 / -32E).** The whole project rests on
the device pretending to be a Bluetooth keyboard, and not every chip in the ESP32 family can do
that.

| Chip | Bluetooth | Use it? |
|---|---|---|
| **ESP32** (WROOM-32, -32D, -32E) | Classic + BLE 4.2 | **Yes.** Best documented, every BLE-HID library targets it. |
| ESP32-S3 | BLE 5.0 only | Works, but fewer copy-paste examples. |
| ESP32-C3 | BLE 5.0 only | Works. Cheap, single core, less RAM. |
| **ESP32-S2** | **None at all** | **No.** It has Wi-Fi and no Bluetooth whatsoever. |
| **ESP8266 / ESP8266EX** | **None at all** | **No.** Wi-Fi only. See below. |

The ESP32-S2 trap is easy to fall into — it is sold on boards that look identical to ESP32 ones
and is sometimes cheaper. If the listing does not say "Bluetooth", do not buy it.

### The ESP8266 is not a smaller ESP32

They are different chips from different generations, and the ESP8266EX has **no Bluetooth
hardware of any kind** — not Classic, not BLE. No library or firmware can add it, because the
radio is 802.11 b/g/n only. Any "ESP8266 Bluetooth" result you find online is either an external
module doing the work or simply wrong.

An ESP8266 can still run most of this project: the display, the encoder, the state machine, the
key derivation, the AES-GCM storage. It cannot do step 8 and step 9 of the specified algorithm,
which is where the credential is actually delivered. If an ESP8266 is what you have, see §11 for
what to build on it today and what the alternatives are.

Prefer a **WROOM-32E** (rev 3 silicon). Rev 3 supports Secure Boot v2, which you will want in
§7 if you take the security side all the way.

---

## 1. Core parts — phase 1, breadboard

Everything needed to get the firmware running and demonstrable over USB power.

| # | Part | Spec that matters | Qty | ₹ approx |
|---|---|---|---|---|
| 1 | ESP32 DevKit V1 / DevKitC | 30-pin or 38-pin, WROOM-32E, USB-UART onboard (CP2102 or CH340) | 2 | 350–650 ea |
| 2 | OLED display | 0.96", **128×64**, **SSD1306**, **I²C (4-pin)**, 3.3 V tolerant | 2 | 150–250 ea |
| 3 | Rotary encoder | **EC11** with integrated push switch, 20 detents | 2 | 40–80 ea |
| 4 | Breadboard | 830-point | 1 | 80–150 |
| 5 | Jumper wires | M-M and M-F, 20 cm | 1 set | 100–150 |
| 6 | USB cable | micro-USB **data** cable, not charge-only | 1 | 100–150 |

**Buy two of items 1–3.** Boards get fried, OLEDs arrive dead, and you want a spare working unit
on the bench the night before a review. The cost of a spare ESP32 is far less than the cost of
not having one.

### Notes on the OLED

Get the **4-pin I²C** version (VCC, GND, SCL, SDA), not the 7-pin SPI one. Default address is
`0x3C`; a few modules are `0x3D`, so run an I²C scanner first if nothing appears.

The 1.3" displays sold alongside these are usually **SH1106**, not SSD1306. They work, but they
need a different driver and have a 2-pixel column offset that will leave your display looking
shifted. If you buy 1.3", use u8g2 with an SH1106 constructor and expect to fix the offset.

### Notes on the encoder

A bare EC11 soldered to a breakout is better than a KY-040 module — the KY-040's onboard
pull-ups are fine, but it has no filtering, and encoder bounce is the single most common reason
a menu jumps two entries per click. Plan to add the RC filter in §4 regardless.

---

## 2. Power — phase 2, portable

Only once the firmware works on USB. Do not debug firmware and power electronics at the same
time.

| # | Part | Spec that matters | Qty | ₹ approx |
|---|---|---|---|---|
| 7 | Li-Po cell | 3.7 V, 1000 mAh, JST-PH 2.0, **with built-in PCM** | 1 | 200–350 |
| 8 | TP4056 charger module | **The version WITH protection** — has DW01A + 8205A chips and B+/B−/OUT+/OUT− pads | 1 | 30–60 |
| 9 | Boost converter | MT3608, adjustable, set to 5.0 V | 1 | 40–70 |
| 10 | Slide switch | SPDT, panel mount | 1 | 10–20 |
| 11 | Piezo buzzer | Passive, 3.3 V | 1 | 15–30 |

### The power architecture to use

```
USB-C/micro ──► TP4056 (protected) ──► Li-Po 3.7 V
                                          │
                              slide switch┤
                                          ▼
                               MT3608 boost → 5.0 V ──► ESP32 "5V"/VIN pin
                                                            │
                                                     onboard AMS1117 → 3.3 V rail
```

Set the MT3608 to **exactly 5.0 V with a multimeter before connecting it to anything**. It ships
at an arbitrary voltage and the trimpot is ~20 turns; feeding 12 V into your ESP32 ends the
build.

**Why boost to 5 V instead of feeding the battery straight in?** The DevKit's AMS1117 regulator
needs about 1.1 V of headroom, so a 3.7 V battery on VIN produces a 3.3 V rail that sags and
browns out. Going up to 5 V first lets the onboard regulator do its normal job.

**Simpler alternative:** battery straight onto the **3.3 V pin**, bypassing the regulator
entirely. Fewer parts and better efficiency, but two hard rules — never connect USB at the same
time (you would back-feed the regulator output), and accept that the device dies at around
3.0 V with maybe 10% of the charge left.

### Two power gotchas

**TP4056 modules have no load-sharing.** If the device draws current from the battery while the
module is charging it, the charger misreads the battery and may never terminate. Either charge
with the slide switch off (fine for this project, document it as a limitation), or move to an
IP5306-based module that does charging, boosting and power-path in one part.

**Set the charge current.** A stock TP4056 charges at 1 A, which is 1C for a 1000 mAh cell and
2C for a 500 mAh one — too aggressive. Charge current is `I(mA) = 1200000 / R_prog(Ω)`. Swap the
1.2 kΩ programming resistor for **2.4 kΩ (500 mA)** or **5.1 kΩ (235 mA)**.

### Expected battery life

ESP32 with BLE advertising and the OLED lit draws roughly 80–130 mA, so a 1000 mAh cell gives
you **about 6–9 hours of active use**. That is poor for a product and fine for a prototype. The
fix is `esp_deep_sleep_start()` with wake on the encoder button, which drops idle draw to tens
of microamperes and turns it into weeks of standby. Worth implementing if you have time — it is
also exactly what a real vault does, and a good thing to be asked about.

---

## 3. Enclosure and assembly

| # | Part | Notes | ₹ approx |
|---|---|---|---|
| 12 | 3D-printed case | Two-part, friction fit, cutouts for OLED window, knob shaft, USB port, switch | 200–600 |
| 13 | Knob | 6 mm D-shaft to match the EC11 | 20–50 |
| 14 | Perfboard / zero PCB | 7×5 cm, for the soldered build | 30–60 |
| 15 | Header pins + sockets | Female headers so the ESP32 is removable | 20–50 |
| 16 | M2 screws and standoffs | 6–10 mm | 50–100 |

Socket the ESP32 on female headers rather than soldering it down. You will want to pull it out.

If your campus has a 3D printer, the case is free and you can iterate; otherwise a small ABS
project box with a Dremel-cut window is perfectly respectable.

---

## 4. Passives

Small parts, but three of them are not optional.

| Part | Value | Qty | Why |
|---|---|---|---|
| **Electrolytic capacitor** | **470 µF or 1000 µF, 10 V** | 1 | **Across the 3.3 V rail next to the module.** BLE transmit bursts draw 300 mA+ spikes; without bulk capacitance the rail dips and the ESP32 brownout-resets mid-demo. This is the most common ESP32 hardware failure there is. |
| **Ceramic capacitors** | **100 nF** | 3 | **Two from encoder A and B to ground, one from the switch to ground.** With the 10 kΩ pull-ups this forms a ~1 ms RC filter and kills contact bounce in hardware. |
| Resistors | 10 kΩ | 3 | Pull-ups for encoder A, B and switch (skip if using a KY-040, which has its own). |
| Ceramic capacitor | 100 nF | 2 | Decoupling at the module's 3.3 V and the OLED's VCC. |
| Resistor | 2.4 kΩ or 5.1 kΩ | 1 | TP4056 charge-current programming (see §2). |

An assorted resistor and capacitor kit (₹100–200) covers all of this and the next project too.

---

## 5. Tools

If the team already has these, skip. If not, this is the realistic minimum.

| Tool | Notes | ₹ approx |
|---|---|---|
| Soldering iron | 25–60 W temperature-controlled if possible | 400–1500 |
| Solder wire | 60/40, 0.8 mm, with flux core | 100–200 |
| **Multimeter** | **Non-negotiable.** You need it to set the boost converter and to find the short you will eventually create. | 400–900 |
| Wire strippers / flush cutters | | 150–300 |
| Desoldering braid or pump | You will need it | 50–150 |
| Helping hands / vice | Optional but transforms soldering | 200–500 |

---

## 6. Pin map

Matches the pin assignments already documented in the simulator's boot log, so the firmware port
lines up with the docs.

| Signal | GPIO | Notes |
|---|---|---|
| OLED SDA | 21 | Default I²C SDA |
| OLED SCL | 22 | Default I²C SCL |
| OLED VCC | 3V3 | |
| OLED GND | GND | |
| Encoder A (CLK) | 32 | 10 kΩ pull-up + 100 nF to GND |
| Encoder B (DT) | 33 | 10 kΩ pull-up + 100 nF to GND |
| Encoder switch | 25 | 10 kΩ pull-up + 100 nF to GND; also the deep-sleep wake pin |
| Piezo buzzer | 26 | PWM / LEDC channel |
| Status LED | 2 | Onboard LED on most DevKits |

**GPIOs to avoid on ESP32:** 6–11 are wired to the SPI flash and will brick the boot if you use
them. 34–39 are input-only with no internal pull-ups. 0, 2, 12 and 15 are strapping pins —
pulling them the wrong way at reset stops the board booting. The map above deliberately avoids
all of these except GPIO 2, which is safe as an output-only LED.

---

## 7. Firmware stack

| Need | Use | Note |
|---|---|---|
| BLE HID keyboard | `ESP32-BLE-Keyboard` (T-vK), or NimBLE directly | NimBLE saves roughly 100 KB of flash over Bluedroid — you will want it once mbedTLS is linked in |
| Display | `Adafruit_SSD1306` + `Adafruit_GFX`, or `u8g2` | u8g2 has more fonts and supports SH1106 |
| Encoder | ESP32 **PCNT** peripheral with its glitch filter | Hardware quadrature decoding. Far better than interrupts, and a strong answer when asked how you handled bounce |
| PBKDF2 | `mbedtls_pkcs5_pbkdf2_hmac()` | Built into ESP-IDF |
| HKDF | `mbedtls_hkdf()` | |
| AES-256-GCM | `mbedtls_gcm_crypt_and_tag()` | Hardware-accelerated on ESP32 |
| RNG | `esp_fill_random()` | True RNG when the RF subsystem is active |
| Storage | `nvs_flash` + `nvs_set_blob()` | Maps directly onto the simulator's NVS model |
| Wipe secrets | `mbedtls_platform_zeroize()` | Will not be optimised away, unlike `memset` |

**Lower the PBKDF2 iteration count.** The simulator uses 150,000 because a laptop does that in
50 ms. An ESP32 manages roughly 8–12k iterations per second in software, so 150,000 would take
around 15 seconds per unlock. Use **20,000** and measure it, or enable the SHA hardware
accelerator and re-measure. Either way, state the measured number — a reviewer who knows
embedded will ask.

### If you take security all the way

Flash Encryption and Secure Boot v2 are what stop someone pulling your firmware off the chip or
replacing it. Both burn **eFuses, which are permanent and irreversible**.

Use **Development mode** while building — it lets you reflash. Only consider Release mode on a
board you are willing to never reprogram again. Do not burn eFuses on your only ESP32 the week
of a submission.

---

## 8. Budget

Indicative Indian retail, late 2026. Verify against current listings.

| | ₹ |
|---|---|
| Core parts, single unit | 600–1,000 |
| Spares (2nd ESP32, OLED, encoder) | 550–1,000 |
| Battery and power | 300–500 |
| Enclosure and assembly | 300–800 |
| Passives | 150–250 |
| **Total build** | **₹1,900–3,550** |
| Tools, if starting from nothing | +₹1,300–3,500 |

## 9. Where to buy

**Online, ships across India:** Robu.in (widest stock, reliable), Quartz Components,
ElectronicsComp, Evelta, Sunrom, ThinkRobotics. Amazon.in works for the common parts but
descriptions are unreliable — verify the chip variant before buying.

**Local markets** are faster and let you test before paying: SP Road (Bengaluru), Lamington Road
(Mumbai), Ritchie Street (Chennai), Lajpat Rai Market (Delhi).

Order the Li-Po from a proper electronics supplier, not a marketplace reseller. Cheap cells with
no protection circuit are a genuine fire risk.

---

## 10. Suggested order of work

1. **Breadboard, USB powered.** ESP32 + OLED only. Get "hello world" on the display.
2. **Add the encoder.** Get clean, bounce-free menu navigation. Budget real time for this.
3. **Port the state machine** from the simulator. Same states, same screens.
4. **Add crypto.** PBKDF2 → HKDF → AES-GCM against NVS. Measure the unlock time.
5. **Add BLE HID.** Pair with a laptop, type a fixed string, then the real credential.
6. **Add power.** Battery, charger, boost, switch. Only now.
7. **Enclosure.** Measure twice; the OLED window is unforgiving.
8. **Deep sleep,** if time allows.

Keep the simulator working throughout — it is your reference implementation, and if the hardware
misbehaves the night before a review, it is also your demo.

---

## 11. If you already have an ESP8266

The ESP8266EX has no Bluetooth, so it cannot be the final device for a project called a
*Bluetooth* password vault. The recommendation is to buy an ESP32 DevKit — at ₹350–650 it costs
less than every workaround below, and the ESP8266 stays useful as a Wi-Fi board for something
else.

That said, you are not blocked from starting today. Roughly 80% of the firmware is transport-
independent and ports straight across.

### What runs on an ESP8266 unchanged

| Works | Note |
|---|---|
| SSD1306 OLED over I²C | Same `Adafruit_SSD1306` / `u8g2` code |
| EC11 rotary encoder | Interrupt-driven; no PCNT peripheral, so the 100 nF filter caps matter more |
| The whole state machine and UI | Boot, password entry, menu, detail, settings, auto-lock |
| PBKDF2 → HKDF → AES-256-GCM | Via BearSSL (bundled with the ESP8266 Arduino core) or mbedTLS |
| Persistent encrypted storage | **LittleFS**, not NVS — `nvs_flash` is an ESP-IDF API and does not exist here |

### What does not

Steps 8–9: establishing the BLE HID link and transmitting the keystrokes. There is no radio for
it and no USB peripheral either.

### ESP8266 pin map

Avoids every strapping pin. Assumes a NodeMCU or Wemos D1 mini — a bare ESP-01 has far too few
GPIOs for this build.

| Signal | GPIO | NodeMCU label |
|---|---|---|
| OLED SDA | 4 | D2 |
| OLED SCL | 5 | D1 |
| Encoder A | 12 | D6 |
| Encoder B | 14 | D5 |
| Encoder switch | 13 | D7 |
| Buzzer | 15 | D8 — note this pin must be LOW at boot |

**Do not use** GPIO0, GPIO2 or GPIO15 for inputs that could be pulled the wrong way at reset, and
remember GPIO16 (D0) supports neither interrupts nor an internal pull-up, so it is useless for
the encoder.

### Porting caveats

**Key derivation is slower.** The ESP8266 is a single 80 MHz core with no SHA or AES accelerator,
so PBKDF2 runs slower than on an ESP32, which is itself far slower than the laptop figure of
150,000 iterations. Start at **5,000**, measure the actual unlock time, and quote the measured
number.

**Less RAM.** Around 40–50 KB of usable heap. Fine for this project, but do not hold more than
one decrypted credential at a time — which the design already requires.

**No flash encryption and no Secure Boot.** These are ESP32 features built on eFuses the ESP8266
does not have. Worth being precise about what that costs:

* It does **not** break the storage design. The vault key is derived from the master password and
  never written to flash, so a flash dump still yields only ciphertext. That part holds.
* It **does** remove firmware integrity. An attacker with the board can reflash it with a version
  that captures the master password. On ESP32 you would burn Secure Boot to prevent exactly
  this.

That is a clean, honest limitation to state in a review rather than something to hide.

### If buying an ESP32 is genuinely not an option

| Approach | What you get | What it costs you |
|---|---|---|
| **Add a UART-to-USB-HID bridge** (CH9329 or CH9328, ₹300–500) | The ESP8266 sends the credential over serial and the bridge types it as a real USB keyboard. Keeps the "no software on the host" property intact. | It is now a **wired USB** vault. The project is no longer Bluetooth, and the title has to change. |
| **Wi-Fi plus a helper app on the PC** | Uses the radio the chip actually has. | Badly weakens the security story: the host now runs a trusted agent, credentials cross a network, and the "appears as an ordinary keyboard, needs no drivers" argument is gone. Hardest option to defend in a review. |
| **Bolt on a BLE-HID module** | Keeps Bluetooth. | The convenient ones (Adafruit EZ-Key, RN-42-HID) are discontinued or cost more than an ESP32. HC-05 and HM-10 **cannot** do HID — they are serial profiles only. Not worth it. |

If you have to pick one of these, the CH9329 bridge is the only one that keeps the security
argument intact. But an ESP32 is cheaper than the bridge and keeps the project as specified.

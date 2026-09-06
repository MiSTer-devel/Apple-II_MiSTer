# wdc65c02 - WDC 65C02 core (canonical)

The WDC 65C02 (W65C02S-style) core for this project
Tested to match known real hardware behavior via SingleStepTests and perfect6502 reference.

- WDC_MODE=1: WDC 65C02 behaviour (wdc/rockwell/synertek variants).
- WDC_MODE=0: same core's NMOS-6502 behaviour; do not use this if you need exact 6502 behavior (see below)

Companion core: `rtl/cpu/nmos6502/` 
(the NMOS 6502 core, netlist derived, with its own README). 
This variant matches real NMOS 6502 behavior more accurately.


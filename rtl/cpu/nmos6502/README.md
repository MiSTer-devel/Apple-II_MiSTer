65C02 CPU core specialized for 6502 mode
Copyright (c) 2026 Jamie Blanks

This is a variant of the 65C02 with tweaks to match NMOS 6502,
to be used in contexts where the original machine had the NMOS chip (e.g. Atari 7800)

Both NMOS and WDC chips are largely compatible but ultimately a different chip.
If we want to be cycle accurate we need to treat each one differently.

Comparison vs. the WDC version:
- netlist derived
- fixed some of the pin definitions there
- irq timing is speculative based on 6502, since it's undefined by pretty much anything

For an FPGA core needing both 6502 and 65C02, the two CPUs can be on the bus; 
"just keep the unused one with rdy low"


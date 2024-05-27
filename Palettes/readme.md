# Color palettes for Apple II

Each file contains 16 colors in RGBA format.

Palettes have been split in two folders:

* *Realistic*  

Palettes attempting to replicate either exact standard Apple II colors, 
or variations from other computers of the era (e.g. NTSC for C64 at different settings)

* *Fantasy*

These do not necessarly follow standard colors or any existing computer;
they will give your display a different feel and can fit some games or specific esthetics very well.

## Customizing palettes

An a2p file can be created or edited with a hex editor such as HxD. 

Each color is defined as four bytes (R,G,B and 00 to separate), and they must be ordered as follows:

0. Black       *(Hi-Res color 0 and 3)*
1. Magenta
2. Dark Blue
3. Purple      *(Hi-Res color 2)*
4. Dark Green
5. Gray 1      (darker)
6. Medium Blue *(Hi-Res color 6)*
7. Light Blue
8. Brown
9. Orange      *(Hi-Res color 5)*
10. Gray 2     (identical or lighter than Gray 1)
11. Pink
12. Green      *(Hi-Res color 1)*
13. Yellow
14. Aquamarine
15. Black      *(Hi-Res color 4 and 7)*

The palette can be loaded from the FPGA core at any time via OSD option.







 





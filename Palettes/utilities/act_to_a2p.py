# ACT palette to A2P converter
# e.g. to process files from colodore.com
#
# usage:  acta2p.py  <file.act> 
# output: .a2p file
#
from argparse import ArgumentParser

def processFile(filename):
    '''read binary file and output in a2p format'''
    outFile = filename.replace(".act","") + ".a2p"
    colors = []
    # extract colors from file
    with open(filename, 'rb') as f:
        rgb = 0
        label = ''
        barray = []
        while(byte := f.read(1)):
            barray.append(byte)
            label +=  byte.hex()
            rgb += 1
            if rgb > 2:
                print(label)
                colors.append(barray)
                label = ''
                barray = []
                rgb = 0
                if len(colors) == 16:
                    break
    # map colodore c64 colors to Apple2 order
    colorMap = {'BLACK': colors[0],
                'MAGENTA': colors[2],
                'DARK_BLUE': colors[6],
                'PURPLE': colors[4],
                'DARK_GREEN': colors[5],
                'GRAY': colors[11],
                'MEDIUM_BLUE': colors[14],
                'LIGHT_BLUE': colors[3],
                'BROWN': colors[9],
                'ORANGE': colors[8],
                'GRAY2': colors[12],
                'PINK': colors[10],
                'GREEN': colors[13],
                'YELLOW': colors[7],
                'AQUAMARINE': colors[15],
                'WHITE': colors[1],
                }
    def writeColor(f, color):
        for bt in color:
            f.write(bt)
        f.write(bytes(1)) # add 4th byte for RGBA format
    with open(outFile, 'wb') as fout:
        # order matters
        writeColor(fout, colorMap['BLACK'])
        writeColor(fout, colorMap['MAGENTA'])
        writeColor(fout, colorMap['DARK_BLUE'])
        writeColor(fout, colorMap['PURPLE'])
        writeColor(fout, colorMap['DARK_GREEN'])
        writeColor(fout, colorMap['GRAY'])
        writeColor(fout, colorMap['MEDIUM_BLUE'])
        writeColor(fout, colorMap['LIGHT_BLUE'])
        writeColor(fout, colorMap['BROWN'])
        writeColor(fout, colorMap['ORANGE'])
        writeColor(fout, colorMap['GRAY2'])
        writeColor(fout, colorMap['PINK'])
        writeColor(fout, colorMap['GREEN'])
        writeColor(fout, colorMap['YELLOW'])
        writeColor(fout, colorMap['AQUAMARINE'])
        writeColor(fout, colorMap['WHITE'])
    print("\nApple2 palette file saved as: %s" % outFile)
        

parser = ArgumentParser()
parser.add_argument("-f", "--file", dest="filename",
                    help="input .act palette file(Adobe Color Table)", metavar="FILE")

args = parser.parse_args()    

if args.filename is None:
    print ("Please provide filename e.g. -f palette.act")
elif '.act' not in args.filename.strip().lower():
    print ("Input file must be .act")
else:
    processFile(args.filename)
    


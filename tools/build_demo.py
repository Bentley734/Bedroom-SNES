"""Build the original, freely redistributable Bedroom SNES test cartridge.

No assembler or Nintendo game assets are required. D-pad scrolls the picture;
Start recenters it. This is genuine 65816 code running through the emulator.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FONT={
'A':['01110','10001','10001','11111','10001','10001','10001'],
'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'],
'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'],
'F':['11111','10000','10000','11110','10000','10000','10000'],
'G':['01111','10000','10000','10111','10001','10001','01111'],
'H':['10001','10001','10001','11111','10001','10001','10001'],
'I':['111','010','010','010','010','010','111'],
'K':['10001','10010','10100','11000','10100','10010','10001'],
'L':['10000','10000','10000','10000','10000','10000','11111'],
'M':['10001','11011','10101','10101','10001','10001','10001'],
'N':['10001','11001','10101','10011','10001','10001','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'],
'P':['11110','10001','10001','11110','10000','10000','10000'],
'R':['11110','10001','10001','11110','10100','10010','10001'],
'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'U':['10001','10001','10001','10001','10001','10001','01110'],
'V':['10001','10001','10001','10001','10001','01010','00100'],
'W':['10001','10001','10001','10101','10101','10101','01010'],
'X':['10001','10001','01010','00100','01010','10001','10001'],
'Y':['10001','10001','01010','00100','00100','00100','00100'],
}
class Asm:
    def __init__(self):self.code=bytearray();self.labels={};self.refs=[]
    def emit(self,*values):self.code.extend(values)
    def label(self,name):self.labels[name]=0x8000+len(self.code)
    def jump(self,op,name):self.emit(op,0,0);self.refs.append((len(self.code)-2,name,False))
    def branch(self,op,name):self.emit(op,0);self.refs.append((len(self.code)-1,name,True))
    def store(self,value,address):self.emit(0xa9,value,0x8d,address&255,address>>8)
    def finish(self):
        for at,name,relative in self.refs:
            value=self.labels[name]
            if relative:
                offset=value-(0x8000+at+1);assert -128<=offset<=127
                self.code[at]=offset&255
            else:self.code[at:at+2]=value.to_bytes(2,'little')
        return self.code

def build():
    a=Asm();a.label('reset')
    a.emit(0x78,0x18,0xfb,0xc2,0x30,0xa2,0xff,0x1f,0x9a,0xa9,0,0,0x5b,0xe2,0x20)
    for value,reg in [(0x80,0x2100),(0,0x4200),(0,0x420c),(1,0x2105),(0x10,0x2107),(0,0x210b),(1,0x212c),(0,0x212d),(0,0x2130),(0,0x2131),(0x80,0x2115),(0,0x2121)]:a.store(value,reg)
    # Palette: dark blue, mint white, teal, lavender.
    for color in [0x1042,0x7ff7,0x5b05,0x75b5]:
        a.store(color&255,0x2122);a.store(color>>8,0x2122)
    glyphs={' ':0};tiles=bytearray(32)
    for ch,rows in FONT.items():
        glyphs[ch]=len(tiles)//32
        tile=bytearray(32)
        for y,row in enumerate(rows):tile[2*y]=int(row,2)<<1
        tiles+=tile
    # Decorative tile in palette color 2.
    deco=len(tiles)//32;tiles+=bytes([0,0xff]*8+[0]*16)
    tilemap=bytearray(2048)
    for y in range(3,25):
        for x in range(2,30):
            if y in (3,24) or x in (2,29):tilemap[2*(y*32+x)]=deco
    for y,text in [(7,'BEDROOM SNES'),(11,'LUA POWERED'),(16,'DPAD TO SCROLL'),(19,'START TO RECENTER')]:
        for i,ch in enumerate(text):tilemap[2*(y*32+(32-len(text))//2+i)]=glyphs[ch]
    for source,dest,length in [(0x9000,0,len(tiles)),(0xa000,0x1000,len(tilemap))]:
        for value,reg in [(dest&255,0x2116),(dest>>8,0x2117),(1,0x4300),(0x18,0x4301),(source&255,0x4302),(source>>8,0x4303),(0,0x4304),(length&255,0x4305),(length>>8,0x4306),(1,0x420b)]:a.store(value,reg)
    a.emit(0x64,0,0x64,1) # STZ horizontal/vertical scroll in direct page RAM
    a.store(0x81,0x4200);a.store(15,0x2100)
    a.label('wait');a.emit(0xcb);a.jump(0x4c,'wait')
    a.label('nmi');a.emit(0x08,0x48,0xda,0x5a,0xe2,0x20)
    a.emit(0xad,0x10,0x42) # acknowledge NMI
    a.label('joywait');a.emit(0xad,0x12,0x42,0x29,1);a.branch(0xd0,'joywait')
    for mask,opcode,addr,label in [(1,0xe6,0,'left'),(2,0xc6,0,'right'),(4,0xc6,1,'down'),(8,0xe6,1,'up')]:
        a.emit(0xad,0x19,0x42,0x29,mask);a.branch(0xf0,label);a.emit(opcode,addr);a.label(label)
    a.emit(0xad,0x19,0x42,0x29,0x10);a.branch(0xf0,'scroll');a.emit(0x64,0,0x64,1)
    a.label('scroll')
    for zp,reg in [(0,0x210d),(1,0x210e)]:a.emit(0xa5,zp,0x8d,reg&255,reg>>8,0x9c,reg&255,reg>>8)
    a.emit(0x7a,0xfa,0x68,0x28,0x40)
    a.label('irq');a.emit(0x40)
    rom=bytearray([0xff]*32768);code=a.finish();assert len(code)<4096
    rom[:len(code)]=code;rom[0x1000:0x1000+len(tiles)]=tiles;rom[0x2000:0x2800]=tilemap
    rom[0x7fc0:0x7fd5]=b'BEDROOM SNES DEMO    '
    rom[0x7fd5:0x7fdc]=bytes([0x20,0,5,0,1,0,0])
    for offset,label in [(0x7fea,'nmi'),(0x7fee,'irq'),(0x7ffa,'nmi'),(0x7ffc,'reset'),(0x7ffe,'irq')]:rom[offset:offset+2]=a.labels[label].to_bytes(2,'little')
    rom[0x7fdc:0x7fe0]=bytes([0xff,0xff,0,0]);checksum=sum(rom)&65535
    rom[0x7fdc:0x7fde]=(checksum^65535).to_bytes(2,'little');rom[0x7fde:0x7fe0]=checksum.to_bytes(2,'little')
    return bytes(rom)
if __name__=='__main__':
    out=ROOT/'roms/bedroom-demo.sfc';out.write_bytes(build());print(out)

-- Exercise the installed fast renderer inside the actual sandbox and LuaJIT.
return function(screen,check)
  local c=screen.console;local env=c.env
  local fast,reference=c.machine.ppu,env.new(env.Ppu,{})
  for mode=0,7 do
    for _,p in ipairs({fast,reference}) do
      p:reset();p.mode=mode;p.forcedBlank=false;p.frameOverscan=true
      p.directColor=true;p.pseudoHires=true;p.interlace=true;p.evenFrame=true
      p.mode7ExBg=true;p.mode7A=181;p.mode7B=-181;p.mode7C=181;p.mode7D=181
      p.mode7X=128;p.mode7Y=128;p.mode7Hoff=64;p.mode7Voff=-32
      p.addSub=true;p.halfColors=true;p.mosaicSize=5;p.brightness=13
      p.preventMath=2;p.colorClip=1;p.window1Right=191;p.window2Left=96;p.window2Right=223
      for i=0,5 do
        p.mathEnabled[i]=true;p.window1Enabled[i]=true;p.window2Enabled[i]=true;p.windowMaskLogic[i]=2
        if i<5 then
          p.mainScreenEnabled[i]=true;p.subScreenEnabled[i]=i%2==0
          p.mainScreenWindow[i]=true;p.subScreenWindow[i]=true;p.mosaicEnabled[i]=true
        end
        if i<4 then
          p.bgHoff[i]=i*17;p.bgVoff[i]=i*23;p.tilemapAdr[i]=8192+i*1024;p.tileAdr[i]=i*4096
        end
      end
      for i=0,32767 do p.vram[i]=(i*177+63)%65536 end
      for i=0,255 do p.cgram[i]=(i*97)%32768 end
    end
    for _,line in ipairs({1,7,127,224,239}) do
      for _,p in ipairs({fast,reference}) do
        p.window1Left=line%128;p.brightness=line%16
        for x=0,255 do p.spriteLineBuffer[x]=x%3==0 and 0 or 128+x%128;p.spritePrioBuffer[x]=x%4 end
        p:renderLine(line)
      end
      for i=line*1536,line*1536+1535 do assert(fast.pixelOutput[i]==reference.pixelOutput[i],'native mode '..mode..' effects pixel mismatch') end
    end
    check(true,'native Mode '..mode..' effects match reference pixels, including hires/overscan')
  end
  c:reset();for i=1,4 do c:frame() end;screen:video()
end

-- Background-only Mode 1 scanlines. Uses the reference renderer for all
-- other configurations, including sprites, windows, mosaic and color math.
-- Based on SnesJs' tile decoding (MIT, see THIRD_PARTY.txt).
return function(ppu,R)
  local original=ppu.renderLine
  local band,rshift=R.band,R.rshift
  local floor=math.floor
  local ok,bits=pcall(require,'bit')
  if ok then band,rshift=bits.band,bits.rshift end
  ppu.renderLine=function(p,line)
    local eligible=p.mode==1 and not p.forcedBlank and not p.bigTiles[0]
      and not p.mosaicEnabled[0] and not p.pseudoHires and p.colorClip==0
      and p.mainScreenEnabled[0] and not p.mainScreenWindow[0]
    if eligible then
      for i=1,4 do if p.mainScreenEnabled[i] then eligible=false;break end end
      for i=0,5 do if p.mathEnabled[i] then eligible=false;break end end
    end
    if not eligible or line<1 or line>=(p.frameOverscan and 240 or 225) then return original(p,line) end
    if line==1 then p.mosaicStartLine=1 end
    for i=0,3 do p.lastTileFetchedX[i]=-1;p.lastTileFetchedY[i]=-1 end
    p.optHorBuffer[0]=0;p.optHorBuffer[1]=0;p.optVerBuffer[0]=0;p.optVerBuffer[1]=0
    p.lastOrigTileX[0]=-1;p.lastOrigTileX[1]=-1
    local sy=line+p.bgVoff[0]
    local sxStart=p.bgHoff[0]
    local out,colors=p.pixelOutput,p.cgram
    local mult=p.brightnessMults[p.brightness]
    local row=line*1536
    local plane1,plane2,palette,flip
    for x=0,255 do
      local sx=x+sxStart
      local tx=floor(sx/8)
      if tx~=p.lastTileFetchedX[0] then
        p:fetchTileInBuffer(sx,sy,0,false)
        p.lastTileFetchedX[0]=tx;p.lastTileFetchedY[0]=sy
        local word=p.tilemapBuffer[0]
        plane1,plane2=p.tileBufferP1[0],p.tileBufferP2[0]
        palette=band(rshift(word,10),7)*16;flip=band(word,16384)~=0
      end
      local shift=flip and sx%8 or 7-sx%8
      local pixel=band(rshift(plane1,shift),1)+band(rshift(plane1,shift+8),1)*2
        +band(rshift(plane2,shift),1)*4+band(rshift(plane2,shift+8),1)*8
      local color=colors[pixel==0 and 0 or palette+pixel]
      local r=floor(band(color,31)*mult)%256
      local g=floor(band(rshift(color,5),31)*mult)%256
      local b=floor(band(rshift(color,10),31)*mult)%256
      local i=row+x*6
      out[i]=r;out[i+1]=g;out[i+2]=b;out[i+3]=r;out[i+4]=g;out[i+5]=b
    end
    R.clearArray(p.spriteLineBuffer)
    p:evaluateSprites(line)
  end
end

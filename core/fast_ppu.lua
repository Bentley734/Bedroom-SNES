-- Batched Mode 1 scanlines: decode each background once, then resolve priority.
-- Other modes, windows, mosaic, hires and subscreen color math use the SnesJs reference.
-- Original implementation based on SnesJs semantics (MIT, THIRD_PARTY.txt).
return function(ppu,R)
  local original=ppu.renderLine
  local band,rshift=R.band,R.rshift
  local floor=math.floor
  local ok,bits=pcall(require,'bit')
  if ok then band,rshift=bits.band,bits.rshift end
  local pixels,ranks,rankFor,layers={},{},{},{}
  local red,green,blue={},{},{}
  ppu.renderLine=function(p,line)
    local eligible=p.mode==1 and not p.forcedBlank and not p.pseudoHires and p.colorClip==0
    for i=0,4 do
      if p.mainScreenEnabled[i] and (p.mainScreenWindow[i] or p.mosaicEnabled[i]) then eligible=false end
    end
    if p.addSub then eligible=false end
    if not eligible or line<1 or line>=(p.frameOverscan and 240 or 225) then return original(p,line) end
    if line==1 then p.mosaicStartLine=1 end
    for i=0,3 do p.lastTileFetchedX[i]=-1;p.lastTileFetchedY[i]=-1 end
    p.optHorBuffer[0]=0;p.optHorBuffer[1]=0;p.optVerBuffer[0]=0;p.optVerBuffer[1]=0
    p.lastOrigTileX[0]=-1;p.lastOrigTileX[1]=-1
    local modeIndex=p.layer3Prio and 96 or 12
    for j=0,9 do rankFor[p.layersPerMode[modeIndex+j]*4+p.prioPerMode[modeIndex+j]]=j end
    for x=0,255 do pixels[x]=0;ranks[x]=100;layers[x]=5 end
    -- Sprite evaluation remains in the reference implementation, including its
    -- overflow flags and the one-line delay. Only composition is batched here.
    if p.mainScreenEnabled[4] then
      for x=0,255 do
        local pixel=p.spriteLineBuffer[x]
        if pixel~=0 then pixels[x]=pixel;ranks[x]=rankFor[16+p.spritePrioBuffer[x]];layers[x]=4 end
      end
    end
    for layer=0,2 do
      if p.mainScreenEnabled[layer] then
        local sy=line+p.bgVoff[layer]
        local sxStart=p.bgHoff[layer]
        local plane1,plane2,palette,flip,rank
        local four=layer<2
        for x=0,255 do
          local sx=x+sxStart
          local tx=floor(sx/8)
          if tx~=p.lastTileFetchedX[layer] then
            p:fetchTileInBuffer(sx,sy,layer,false)
            p.lastTileFetchedX[layer]=tx;p.lastTileFetchedY[layer]=sy
            local word=p.tilemapBuffer[layer]
            plane1,plane2=p.tileBufferP1[layer],p.tileBufferP2[layer]
            palette=band(rshift(word,10),7)*(four and 16 or 4)
            flip=band(word,16384)~=0
            rank=rankFor[layer*4+band(rshift(word,13),1)]
          end
          if rank<ranks[x] then
            local shift=flip and sx%8 or 7-sx%8
            local pixel=band(rshift(plane1,shift),1)+band(rshift(plane1,shift+8),1)*2
            if four then pixel=pixel+band(rshift(plane2,shift),1)*4+band(rshift(plane2,shift+8),1)*8 end
            if pixel~=0 then pixels[x]=palette+pixel;ranks[x]=rank;layers[x]=layer end
          end
        end
      end
    end
    -- Palette and brightness conversion is shared by all pixels on the line.
    -- Rebuilt each line so CGRAM writes and brightness changes cannot go stale.
    local mult=p.brightnessMults[p.brightness]
    for i=0,255 do
      local color=p.cgram[i]
      red[i]=floor(band(color,31)*mult)%256
      green[i]=floor(band(rshift(color,5),31)*mult)%256
      blue[i]=floor(band(rshift(color,10),31)*mult)%256
    end
    local anyMath=false
    for i=0,5 do if p.mathEnabled[i] then anyMath=true end end
    if p.preventMath==3 or (p.preventMath==1 and not p.window1Enabled[5] and not p.window2Enabled[5]) then anyMath=false end
    local out,row=p.pixelOutput,line*1536
    for x=0,255 do
      local color=pixels[x];local r,g,b=red[color],green[color],blue[color]
      if anyMath and p:getMathEnabled(x,layers[x],color) then
        local raw=p.cgram[color]
        r=band(raw,31);g=band(rshift(raw,5),31);b=band(rshift(raw,10),31)
        local sign=p.subtractColors and -1 or 1
        r=r+sign*p.fixedColorR;g=g+sign*p.fixedColorG;b=b+sign*p.fixedColorB
        if p.halfColors then r=floor(r/2);g=floor(g/2);b=floor(b/2) end
        r=floor(math.max(0,math.min(31,r))*mult)%256
        g=floor(math.max(0,math.min(31,g))*mult)%256
        b=floor(math.max(0,math.min(31,b))*mult)%256
      end
      local i=row+x*6
      out[i]=r;out[i+1]=g;out[i+2]=b;out[i+3]=r;out[i+4]=g;out[i+5]=b
    end
    R.clearArray(p.spriteLineBuffer)
    p:evaluateSprites(line)
  end
end

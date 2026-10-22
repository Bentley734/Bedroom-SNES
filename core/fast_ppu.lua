-- Batched low-resolution Mode 1 renderer. Windows and main/subscreen color
-- math, mosaic and pseudo-hires follow SnesJs; other modes retain the reference.
return function(ppu,R)
  local original=ppu.renderLine
  local band,rshift=R.band,R.rshift
  if R.nativeBit then band,rshift=R.nativeBit.band,R.nativeBit.rshift end
  local floor,min,max=math.floor,math.min,math.max
  local pixels,ranks,layers={},{},{}
  local subPixels,subRanks,subLayers={},{},{}
  local rankFor,red,green,blue={},{},{},{}
  local rawRed,rawGreen,rawBlue={},{},{}
  -- Cache the 5-bit channel operation, including brightness, rather than doing
  -- three clamps, divisions and brightness conversions for every blended pixel.
  -- Tables are bounded by the sixteen brightness values and four operations.
  local blends={}
  local function blendTable(brightness,mult,subtract,half)
    local key=brightness*4+(subtract and 2 or 0)+(half and 1 or 0)
    local result=blends[key]
    if not result then
      result={}
      for a=0,31 do for b=0,31 do
        local value=a+(subtract and -b or b)
        if half then value=floor(value/2) end
        result[a*32+b]=floor(max(0,min(31,value))*mult)%256
      end end
      blends[key]=result
    end
    return result
  end
  local previousColors,previousBrightness={},nil
  local windowStates,windowCache={},{}
  local windowGeneration=0
  local previousLeft1,previousRight1,previousLeft2,previousRight2
  local spread={}
  for byte=0,255 do
    local value,weight,n=0,1,byte
    for bit=0,7 do value=value+(n%2)*weight;n=floor(n/2);weight=weight*16 end
    spread[byte]=value
  end
  local function window(p,x,l)
    local a=p.window1Enabled[l]
    local b=p.window2Enabled[l]
    if not a and not b then return false end
    local w1=x>=p.window1Left and x<=p.window1Right
    local w2=x>=p.window2Left and x<=p.window2Right
    if p.window1Inversed[l] then w1=not w1 end
    if p.window2Inversed[l] then w2=not w2 end
    if not b then return w1 elseif not a then return w2 end
    local logic=p.windowMaskLogic[l]
    if logic==0 then return w1 or w2 elseif logic==1 then return w1 and w2
    elseif logic==2 then return w1~=w2 else return w1==w2 end
  end
  local function prepareWindows(p)
    local changed=previousLeft1~=p.window1Left or previousRight1~=p.window1Right
      or previousLeft2~=p.window2Left or previousRight2~=p.window2Right
    if changed then windowGeneration=windowGeneration+1 end
    for l=0,5 do
      local key=(p.window1Enabled[l] and 1 or 0)+(p.window2Enabled[l] and 2 or 0)
        +(p.window1Inversed[l] and 4 or 0)+(p.window2Inversed[l] and 8 or 0)+p.windowMaskLogic[l]*16
      if not p.window1Enabled[l] and not p.window2Enabled[l] then key=0 end
      local entry=windowCache[key]
      if not entry then entry={states={}};windowCache[key]=entry end
      if entry.generation~=windowGeneration and (key~=0 or not entry.generation) then
        for x=0,255 do entry.states[x]=window(p,x,l) end
        entry.generation=windowGeneration
      end
      windowStates[l]=entry.states
    end
    previousLeft1=p.window1Left;previousRight1=p.window1Right
    previousLeft2=p.window2Left;previousRight2=p.window2Right
  end
  local function fetch(p,sx,sy,l,four)
    local x,y=sx,sy
    local big=p.bigTiles[l]
    if big then x=floor(x/2);y=floor(y/2) end
    local address=p.tilemapAdr[l]+floor(band(y,255)/8)*32+floor(band(x,255)/8)
    if band(x,256)~=0 and p.tilemapWider[l] then address=address+1024 end
    if band(y,256)~=0 and p.tilemapHigher[l] then address=address+(p.tilemapWider[l] and 2048 or 1024) end
    local vram=p.vram
    local word=vram[band(address,32767)]
    local flip=band(word,16384)~=0
    local vertical=band(word,32768)~=0
    local row=sy%8;if vertical then row=7-row end
    local number=band(word,1023)
    if big then
      if band(sx,8)==(flip and 0 or 8) then number=number+1 end
      if band(sy,8)==(vertical and 0 or 8) then number=number+16 end
    end
    local base=p.tileAdr[l]+number*(four and 16 or 8)+row
    local a=vram[band(base,32767)]
    local b=four and vram[band(base+8,32767)] or 0
    p.tilemapBuffer[l]=word;p.tileBufferP1[l]=a
    if four then p.tileBufferP2[l]=b end
    return word,a,b,flip
  end
  local function compose(p,line,enabled,windows,out,depth,layerOut)
    for x=0,255 do out[x]=0;depth[x]=100;layerOut[x]=5 end
    if enabled[4] then
      local mask=windows[4] and (p.window1Enabled[4] or p.window2Enabled[4])
      local size=p.mosaicEnabled[4] and p.mosaicSize or 1
      for x=0,255 do
        local sx=x
        if size>1 then sx=x-x%size end
        local pixel=p.spriteLineBuffer[sx]
        if pixel~=0 and not (mask and windowStates[4][x]) then
          out[x]=pixel;depth[x]=rankFor[16+p.spritePrioBuffer[sx]];layerOut[x]=4
        end
      end
    end
    for layer=0,2 do
      if enabled[layer] then
        local sy=line+p.bgVoff[layer]
        local size=p.mosaicEnabled[layer] and p.mosaicSize or 1
        if size>1 then sy=line-R.rem(line-p.mosaicStartLine,size)+p.bgVoff[layer] end
        local sxStart=p.bgHoff[layer]
        local mask=windows[layer] and (p.window1Enabled[layer] or p.window2Enabled[layer])
        local palette,flip,rank,packed,lastTile
        local four=layer<2
        for x=0,255 do
          local sx=x+sxStart
          if size>1 then sx=x-x%size+sxStart end
          local tx=floor(sx/8)
          if tx~=lastTile then
            local word,a,b
            word,a,b,flip=fetch(p,sx,sy,layer,four)
            lastTile=tx;p.lastTileFetchedX[layer]=tx;p.lastTileFetchedY[layer]=sy
            packed=spread[band(a,255)]+2*spread[rshift(a,8)]
            if four then packed=packed+4*spread[band(b,255)]+8*spread[rshift(b,8)] end
            palette=band(rshift(word,10),7)*(four and 16 or 4)
            rank=rankFor[layer*4+band(rshift(word,13),1)]
          end
          if rank<depth[x] and not (mask and windowStates[layer][x]) then
            local shift=flip and sx%8 or 7-sx%8
            local pixel=band(rshift(packed,shift*4),15)
            if pixel~=0 then out[x]=palette+pixel;depth[x]=rank;layerOut[x]=layer end
          end
        end
      end
    end
  end
  ppu.renderLine=function(p,line)
    local eligible=p.mode==1 and not p.forcedBlank
    if not eligible or line<1 or line>=(p.frameOverscan and 240 or 225) then return original(p,line) end
    if line==1 then p.mosaicStartLine=1 end
    for i=0,3 do p.lastTileFetchedX[i]=-1;p.lastTileFetchedY[i]=-1 end
    p.optHorBuffer[0]=0;p.optHorBuffer[1]=0;p.optVerBuffer[0]=0;p.optVerBuffer[1]=0
    p.lastOrigTileX[0]=-1;p.lastOrigTileX[1]=-1
    local modeIndex=p.layer3Prio and 96 or 12
    for j=0,9 do rankFor[p.layersPerMode[modeIndex+j]*4+p.prioPerMode[modeIndex+j]]=j end
    prepareWindows(p)
    compose(p,line,p.mainScreenEnabled,p.mainScreenWindow,pixels,ranks,layers)
    local anyMath=false
    for i=0,5 do if p.mathEnabled[i] then anyMath=true end end
    if p.preventMath==3 or (p.preventMath==1 and not p.window1Enabled[5] and not p.window2Enabled[5]) then anyMath=false end
    local secondPixels,secondLayers=subPixels,subLayers
    if p.pseudoHires or (anyMath and p.addSub) then
      -- Some effects select the same layers on both screens. Their source
      -- composition is identical even though the final color math differs.
      local same=true
      for l=0,4 do
        if p.mainScreenEnabled[l]~=p.subScreenEnabled[l] or
          (p.mainScreenEnabled[l] and p.mainScreenWindow[l]~=p.subScreenWindow[l]
            and (p.window1Enabled[l] or p.window2Enabled[l])) then same=false;break end
      end
      if same then secondPixels=pixels;secondLayers=layers
      else compose(p,line,p.subScreenEnabled,p.subScreenWindow,subPixels,subRanks,subLayers) end
    end
    local mult=p.brightnessMults[p.brightness]
    local brightnessChanged=mult~=previousBrightness
    for i=0,255 do
      local color=p.cgram[i]
      if brightnessChanged or previousColors[i]~=color then
        rawRed[i]=band(color,31);rawGreen[i]=band(rshift(color,5),31);rawBlue[i]=band(rshift(color,10),31)
        red[i]=floor(rawRed[i]*mult)%256
        green[i]=floor(rawGreen[i]*mult)%256
        blue[i]=floor(rawBlue[i]*mult)%256
        previousColors[i]=color
      end
    end
    previousBrightness=mult
    local fullBlend,halfBlend
    if anyMath then
      fullBlend=blendTable(p.brightness,mult,p.subtractColors,false)
      halfBlend=p.halfColors and blendTable(p.brightness,mult,p.subtractColors,true) or fullBlend
    end
    local out,row=p.pixelOutput,line*1536
    for x=0,255 do
      local color=pixels[x];local layer=layers[x]
      local r,g,b=red[color],green[color],blue[color]
      local inWindow=false
      if p.colorClip==1 or p.colorClip==2 or (anyMath and (p.preventMath==1 or p.preventMath==2)) then inWindow=windowStates[5][x] end
      local clip=p.colorClip==3 or (p.colorClip==2 and inWindow) or (p.colorClip==1 and not inWindow)
      local mathOn=anyMath and p.mathEnabled[layer] and (layer~=4 or color>=192)
        and not (p.preventMath==2 and inWindow) and not (p.preventMath==1 and not inWindow)
      if mathOn then
        r=clip and 0 or rawRed[color];g=clip and 0 or rawGreen[color];b=clip and 0 or rawBlue[color]
        local useSub=p.addSub and secondLayers[x]<5
        local r1,g1,b1=p.fixedColorR,p.fixedColorG,p.fixedColorB
        if useSub then local second=secondPixels[x];r1=rawRed[second];g1=rawGreen[second];b1=rawBlue[second] end
        local blend=(useSub or not p.addSub) and halfBlend or fullBlend
        r=blend[r*32+r1];g=blend[g*32+g1];b=blend[b*32+b1]
      elseif clip then r=0;g=0;b=0 end
      local i=row+x*6
      if p.pseudoHires then
        local second=secondPixels[x]
        out[i]=red[second];out[i+1]=green[second];out[i+2]=blue[second]
      else out[i]=r;out[i+1]=g;out[i+2]=b end
      out[i+3]=r;out[i+4]=g;out[i+5]=b
    end
    R.clearArray(p.spriteLineBuffer)
    p:evaluateSprites(line)
  end
end

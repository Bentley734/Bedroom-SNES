-- Sprite evaluation with scanline-invariant state hoisted out of the loops.
-- Matches the pinned SnesJs evaluator, including its sprite/sliver overflow
-- order and interlaced row selection. No cached OAM/VRAM survives a call.
return function(ppu,R)
  local band,rshift=R.band,R.rshift
  if R.nativeBit then band,rshift=R.nativeBit.band,R.nativeBit.rshift end
  local floor=math.floor
  -- Spread each byte's bits into four-bit lanes. Four planes can then be
  -- combined once per tile row instead of decoded separately for every pixel.
  local spread={}
  for byte=0,255 do
    local value,weight,n=0,1,byte
    for bit=0,7 do value=value+(n%2)*weight;n=floor(n/2);weight=weight*16 end
    spread[byte]=value
  end
  ppu.evaluateSprites=function(p,line)
    local oam,high,vram=p.oam,p.highOam,p.vram
    local colors,priorities=p.spriteLineBuffer,p.spritePrioBuffer
    local sizes,offsets=p.spriteSizes,p.spriteTileOffsets
    local objSize=p.objSize
    local interlace=p.objInterlace
    local heightScale=interlace and 4 or 8
    local field=p.evenFrame and 1 or 0
    local base1,base2=p.sprAdr1,p.sprAdr2
    local index=p.objPriority and band(band(p.oamAdr,254)-2,255) or 254
    local spriteCount,sliverCount=0,0
    for sprite=1,128 do
      local pos=oam[index]
      local attributes=band(rshift(high[rshift(index,4)],band(index,15)),3)
      local size=sizes[objSize+(attributes>=2 and 8 or 0)]
      local row=line-rshift(pos,8)
      local height=size*heightScale
      if row<0 or row>=height then row=row+256 end
      if row>=0 and row<height then
        local x=band(pos,255)+(attributes%2)*256
        if x>255 then x=x-512 end
        if x>-(size*8) then
          if spriteCount==32 then p.rangeOver=true;return end
          if interlace then row=row*2+field end
          local tileWord=oam[index+1]
          local tile=band(tileWord,255)
          local ex=rshift(tileWord,8)
          local adr=base1+(band(ex,1)~=0 and base2 or 0)
          if ex>=128 then row=size*8-1-row end
          local tileRow=rshift(row,3)*8
          row=band(row,7)
          local flip=band(ex,64)~=0
          local palette=128+band(ex,14)*8
          local priority=band(rshift(ex,4),3)
          for k=0,size-1 do
            local left=x+k*8
            if left>-7 and left<256 then
              if sliverCount==34 then p.timeOver=true;return end
              local column=flip and size-1-k or k
              local number=band(tile+offsets[tileRow+column],255)
              local address=adr+number*16+row
              local plane1=vram[band(address,32767)]
              local plane2=vram[band(address+8,32767)]
              local packed=spread[band(plane1,255)]+spread[rshift(plane1,8)]*2
                +spread[band(plane2,255)]*4+spread[rshift(plane2,8)]*8
              local first=left<0 and -left or 0
              local last=left>248 and 255-left or 7
              for j=first,last do
                local shift=(flip and j or 7-j)*4
                local pixel=band(rshift(packed,shift),15)
                if pixel~=0 then colors[left+j]=palette+pixel;priorities[left+j]=priority end
              end
              sliverCount=sliverCount+1
            end
          end
          spriteCount=spriteCount+1
        end
      end
      index=band(index-2,255)
    end
  end
end

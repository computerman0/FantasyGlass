#!/usr/bin/env python3
"""Reproduce the original app icon. Requires Pillow only for icon regeneration."""
from pathlib import Path
from PIL import Image,ImageDraw
import math

size=1024
image=Image.new('RGB',(size,size))
pixels=image.load()
for y in range(size):
    for x in range(size):
        glow=max(0,1-math.hypot((x-270)/950,(y-210)/950))
        pixels[x,y]=(int(7+9*glow),int(18+68*glow),int(35+81*glow))
draw=ImageDraw.Draw(image)
def rotate(u,v):
    a=-math.pi/4
    return (512+u*math.cos(a)-v*math.sin(a),512+u*math.sin(a)+v*math.cos(a))
outline=[]
for u in range(-310,311,2):outline.append(rotate(u,150*(1-(u/310)**2)))
for u in range(310,-311,-2):outline.append(rotate(u,-150*(1-(u/310)**2)))
draw.polygon(outline,fill=(31,190,211))
draw.line(outline+[outline[0]],fill=(167,248,252),width=9,joint='curve')
draw.line([rotate(-130,0),rotate(130,0)],fill=(244,254,255),width=15)
for u in [-90,-45,0,45,90]:draw.line([rotate(u,-32),rotate(u,32)],fill=(244,254,255),width=14)
for u in [-216,216]:
    height=150*(1-(u/310)**2)
    draw.line([rotate(u,-height),rotate(u,height)],fill=(154,243,248),width=18)
image.save(Path(__file__).resolve().parent.parent/'App/Assets.xcassets/AppIcon.appiconset/AppIcon.png',optimize=True)

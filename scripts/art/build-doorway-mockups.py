"""Composite the handover's existing doorway pieces into review images (no new generated art)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'asset/Originals/dungeon-kit/doorways'
OUT=ROOT/'output/doorway-review'; OUT.mkdir(parents=True,exist_ok=True)
OLD=OUT/'current'
FONT=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',24)
def quad(name,x,y):
 im=Image.open(SRC/name).convert('RGBA'); w,h=im.size
 a=np.array(im.crop((x*w//2,y*h//2,(x+1)*w//2,(y+1)*h//2)))
 a[a[:,:,3]<100]=0
 ys,xs=np.nonzero(a[:,:,3]>120)
 return Image.fromarray(a[ys.min():ys.max()+1,xs.min():xs.max()+1])
def fit(im,w,h): return im.resize((w,h),Image.Resampling.LANCZOS)
def wall(name,x,y,w=640,h=384): return fit(quad(name,x,y),w,h)
def plain(name):
 p=quad(name,0,1)
 # An uncracked outside band, tiled across a continuous wall.
 return p.crop((int(p.width*.04),0,int(p.width*.30),int(p.height*.96)))
def leaf(q,w=230,h=255): return fit(quad('lair-leaves-a.png',q%2,q//2),w,h)
def floor_texture(theme):
 material={'lair':'town-cobble','hollow':'forest-floor','mine':'cavern-floor'}[theme]
 im=Image.open(ROOT/f'godot/asset/MAPS/grounds/64x64-tile_19x19_{material}.webp').convert('RGBA')
 return im.crop((256,256,384,384))

def room(theme,lshape=False):
 name={'lair':'lair-north-pieces-b.png','hollow':'hollow-north-pieces-a.png','mine':'mine-north-pieces-a.png'}[theme]
 w,h=(2816,2304) if lshape else (2048,1792)
 im=Image.new('RGBA',(w,h),'#080b13'); mask=Image.new('L',(w,h)); d=ImageDraw.Draw(mask)
 pts=[(128,128),(2688,128),(2688,1152),(1664,1152),(1664,2176),(128,2176)] if lshape else [(128,128),(w-128,128),(w-128,h-128),(128,h-128)]
 d.polygon(pts,fill=255)
 tex=floor_texture(theme); tiled=Image.new('RGBA',(w,h))
 for y in range(0,h,128):
  for x in range(0,w,128): tiled.paste(ImageOps.mirror(tex) if (x//128+y//128)%2 else tex,(x,y))
 im.paste(tiled,(0,0),mask)
 strip=fit(plain(name),128,280)
 for i,(x,y) in enumerate(pts):
  nx,ny=pts[(i+1)%len(pts)]; dx,dy=nx-x,ny-y
  if dy==0:
   for xx in range(min(x,nx),max(x,nx),128):
    p=strip if dx>0 else strip.rotate(180)
    im.alpha_composite(p,(xx,y if dx>0 else y-280))
  else:
   p=strip.rotate(-90 if dy>0 else 90,expand=True)
   for yy in range(min(y,ny),max(y,ny),128): im.alpha_composite(p,(x-280 if dy>0 else x,yy))
 # Three north openings integrated into the same courses.
 north=[(320,'OPEN',None),(1088,'TWO KEYS',0),(1856,'BOSS',1)] if lshape else [(300,'OPEN',None),(1100,'CLOSED',0)]
 for x,label,q in north:
  p=wall(name,0,0,640,384); im.alpha_composite(p,(x,110))
  if q is not None:
   opening=leaf(q) if theme=='lair' else wall(name,1,0,640,384)
   im.alpha_composite(opening,(x+205,235) if theme=='lair' else (x,110))
  if theme=='lair' and q==0:
   locks=Image.open(ROOT/'godot/asset/MAPS/objects/dungeon/padlock-2x1.webp').convert('RGBA')
   lock=fit(locks.crop((0,0,locks.width//2,locks.height)),55,76)
   im.alpha_composite(lock,(x+245,350)); im.alpha_composite(lock,(x+315,350))
  ImageDraw.Draw(im).text((x+200,520),label,font=FONT,fill='#f5dfa5')
 if lshape:
  # Left and lower wall openings: shutter, bolt, intact crack and bombed hole.
  for y,q,label in [(650,2,'SHUTTER'),(1450,3,'BOLT')]:
   p=wall(name,0,0,640,384); p.alpha_composite(leaf(q),(205,125)); p=p.rotate(90,expand=True)
   im.alpha_composite(p,(90,y)); ImageDraw.Draw(im).text((500,y+260),label,font=FONT,fill='#f5dfa5')
  for x,q,label in [(700,0,'CRACKED'),(2050,1,'BLOWN HOLE')]:
   y=1790 if x<1664 else 770
   p=wall(name,q,1,640,384).rotate(180)
   im.alpha_composite(p,(x,y)); ImageDraw.Draw(im).text((x+130,y-45),label,font=FONT,fill='#f5dfa5')
 return im
lair=room('lair',True); lair.convert('RGB').save(OUT/'mockup-lair-room.png')
for theme in ['hollow','mine']:
 room(theme).convert('RGB').save(OUT/f'mockup-{theme}-room.png')
# Both common viewport proportions; the missing part of the L stays dark.
for size,label,origin in [((1024,896),'8x7',(1100,800)),((1593,896),'16x9',(1100,800))]:
 screen=lair.crop((*origin,origin[0]+size[0],origin[1]+size[1]))
 screen.convert('RGB').save(OUT/f'mockup-lair-screen-{label}.png')
# Contact sheet pairs the current game with the proposed room and two material samples.
canvas=Image.new('RGB',(1800,1330),'#10141e'); d=ImageDraw.Draw(canvas)
items=[(OLD/'current-01-lair-hub-north-south-west.png','CURRENT: free-standing door art'),(OUT/'mockup-lair-room.png','PROPOSAL: an L-shaped room, matching wall pieces'),(OUT/'mockup-hollow-room.png','HOLLOW: root-rock doorway study'),(OUT/'mockup-mine-room.png','MINE: timber and crystal doorway study')]
for i,(p,label) in enumerate(items):
 x=(i%2)*900; y=(i//2)*665; d.text((x+24,y+16),label,font=FONT,fill='#f4dfb2')
 thumb=Image.open(p).convert('RGB'); thumb.thumbnail((860,600)); canvas.paste(thumb,(x+(900-thumb.width)//2,y+55))
canvas.save(OUT/'doorway-comparison.png')
print(OUT)

# Compare the current wide viewport with one view of the room outline.
comparison=Image.new('RGB',(1800,600),'#10141e')
d=ImageDraw.Draw(comparison)
for i,(path,label) in enumerate([(OLD/'current-view-lair-r1-16x9.png','CURRENT: neighbouring rooms visible'),(OUT/'mockup-lair-screen-16x9.png','PROPOSED: darkness beyond the room outline')]):
 thumb=Image.open(path).convert('RGB'); thumb.thumbnail((870,530))
 comparison.paste(thumb,(i*900+(900-thumb.width)//2,60))
 d.text((i*900+20,20),label,font=FONT,fill='#f4dfb2')
comparison.save(OUT/'viewport-comparison.png')

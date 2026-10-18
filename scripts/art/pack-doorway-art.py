"""Pack existing doorway study sheets into runtime wall pieces and separate door leaves."""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'asset/Originals/dungeon-kit/doorways'
OUT=ROOT/'godot/asset/MAPS/objects/dungeon/doorways';OUT.mkdir(parents=True,exist_ok=True)
def quad(name,x,y):
 im=Image.open(SRC/name).convert('RGBA');w,h=im.size
 a=np.array(im.crop((x*w//2,y*h//2,(x+1)*w//2,(y+1)*h//2)));a[a[:,:,3]<80]=0
 ys,xs=np.nonzero(a[:,:,3]>100)
 return Image.fromarray(a[ys.min():ys.max()+1,xs.min():xs.max()+1])
def save(im,name,size): im.resize(size,Image.Resampling.LANCZOS).save(OUT/(name+'.webp'),lossless=True)
for style,sheet in [('masonry','lair-north-pieces-b.png'),('root-rock','hollow-north-pieces-a.png'),('crystal-rock','mine-north-pieces-a.png')]:
 for suffix,x,y in [('arch',0,0),('cracked',0,1),('blown',1,1)]:
  im=quad(sheet,x,y)
  # Widen only the opening's central band; keep the stone jambs at their original proportion.
  if suffix=='arch':
   w,h=im.size;a=int(w*.38);b=int(w*.62);extra=max(0,int(h*256/384)-(b-a))
   p=Image.new('RGBA',(w+extra,h));p.paste(im.crop((0,0,a,h)),(0,0));p.paste(im.crop((a,0,b,h)).resize((b-a+extra,h)),(a,0));p.paste(im.crop((b,0,w,h)),(b+extra,0));im=p
  save(im,style+'-'+suffix,(704,384))
 plain=quad(sheet,0,1);w,h=plain.size;save(plain.crop((int(w*.04),0,int(w*.28),h)),style+'-plain',(128,384))
for n,(x,y) in enumerate([(0,0),(1,0),(0,1),(1,1)]): save(quad('lair-leaves-a.png',x,y),['oak-leaf','boss-leaf','shutter-leaf','bolt-leaf'][n],(256,256))
# Cave rock uses the game's existing stone, cut into the same arch silhouette.
wall=Image.open(ROOT/'godot/asset/MAPS/elevation/cave-rock-wall.png').convert('RGBA')
canvas=wall.resize((704,384));d=ImageDraw.Draw(canvas);d.rectangle((224,220,480,384),fill='#080b12');d.ellipse((224,88,480,344),fill='#080b12');save(canvas,'cave-rock-arch',(704,384))
save(wall,'cave-rock-plain',(128,384))
for suffix,source in [('cracked','crack-overlay.webp'),('blown','hole-overlay.webp')]:
 im=wall.resize((704,384));overlay=Image.open(ROOT/'godot/asset/abilities/goo-bomb'/source).convert('RGBA');overlay.thumbnail((300,300));im.alpha_composite(overlay,((704-overlay.width)//2,384-overlay.height));save(im,'cave-rock-'+suffix,(704,384))
print(OUT)

# Keep the existing two-frame state machines, with only their central leaves/boards.
for source,name in [
 ('godot/asset/MAPS/objects/fattys-lair/plank-barricade-2x1.webp','barricade-leaves'),
 ('godot/asset/MAPS/props/mine/256x256-tile_2x1-mine-gate.webp','mine-gate-leaves'),
 ('godot/asset/MAPS/props/mine/256x256-tile_2x1-rotten-timbers.webp','rotten-leaves')]:
 im=Image.open(ROOT/source).convert('RGBA');fw=im.width//2;h=im.height
 sheet=Image.new('RGBA',(512,256))
 for i in range(2):
  leaf=im.crop((i*fw+int(fw*.17),int(h*.22),(i+1)*fw-int(fw*.17),h)).resize((256,256),Image.Resampling.LANCZOS)
  sheet.alpha_composite(leaf,(i*256,0))
 sheet.save(OUT/(name+'.webp'),lossless=True)

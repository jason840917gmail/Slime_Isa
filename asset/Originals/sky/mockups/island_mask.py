import sys
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
def island_mask(path, seeds, out_png, dbg_png=None, cut_below=None):
    im=Image.open(path).convert('RGB')
    a=np.asarray(im).astype(np.float32)/255
    r,g,b=a[...,0],a[...,1],a[...,2]
    mx=a.max(-1); mn=a.min(-1); sat=(mx-mn)/(mx+1e-6)
    green=((g>=r*0.95)&(g>b*1.25)&(sat>0.35))
    v=np.where(green,255,0).astype(np.uint8)
    bi=Image.fromarray(np.stack([v,v,v],-1),'RGB')
    for s in seeds:
        ImageDraw.floodfill(bi,s,(128,0,0),thresh=0)
    low=np.asarray(bi)[...,0]==128
    m=Image.fromarray(np.where(low,0,255).astype(np.uint8),'L')
    # close tiny specks, then soften
    m=m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    m=m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    if cut_below is not None:
        d=ImageDraw.Draw(m); d.rectangle([0,cut_below,m.size[0],m.size[1]],fill=0)
    m.save(out_png)
    if dbg_png:
        dbg=im.copy(); dbg.paste((255,0,255),mask=Image.eval(m,lambda x:255-x))
        dbg.resize((dbg.size[0]//2,dbg.size[1]//2)).save(dbg_png)
    return m
if __name__=='__main__':
    S=sys.argv[1]+'/'
    island_mask(S+'render1/f00000049.png',[(1000,1000),(1500,300),(1550,1100)],S+'mask1.png',S+'mask1_dbg.png',cut_below=1520)

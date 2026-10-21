"""Original book-and-bookmark icon. Regenerate with Pillow."""
from PIL import Image,ImageDraw
from pathlib import Path
import json
S=2048
im=Image.new('RGB',(S,S),'#fff7ed');d=ImageDraw.Draw(im)
d.rounded_rectangle((270,290,1778,1758),radius=290,fill='#f6e3e5')
d.rounded_rectangle((474,480,1610,1540),radius=90,fill='#a93e60')
d.rounded_rectangle((420,420,1550,1480),radius=90,fill='#fffdf8')
d.rectangle((420,500,525,1400),fill='#ead8cf')
d.polygon([(1190,420),(1350,420),(1350,930),(1270,855),(1190,930)],fill='#bd5877')
for y,w in [(900,460),(1050,570),(1200,400)]:d.rounded_rectangle((670,y,670+w,y+27),radius=13,fill='#b7b0a7')
out=Path('App/Assets.xcassets/AppIcon.appiconset');out.mkdir(parents=True,exist_ok=True)
entries=[]
for pt,scale in [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)]:
    name=f'icon-{pt}@{scale}x.png';im.resize((pt*scale,pt*scale),Image.Resampling.LANCZOS).save(out/name)
    entries.append(dict(size=f'{pt}x{pt}',idiom='iphone',filename=name,scale=f'{scale}x'))
im.resize((1024,1024),Image.Resampling.LANCZOS).save(out/'icon-1024.png')
entries.append(dict(size='1024x1024',idiom='ios-marketing',filename='icon-1024.png',scale='1x'))
(out/'Contents.json').write_text(json.dumps(dict(images=entries,info=dict(version=1,author='xcode')),indent=2)+'\n')
Path('App/Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')

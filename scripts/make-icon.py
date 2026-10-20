"""Original flower-and-book artwork; requires Pillow only when regenerating."""
from PIL import Image,ImageDraw
from pathlib import Path
import math,json
S=2048
im=Image.new('RGB',(S,S),'#fff7ed');d=ImageDraw.Draw(im)
d.ellipse((235,165,1810,1740),fill='#f8e2de')
d.ellipse((370,350,1700,1680),fill='#f4d6d5')
# Open book with a heart-like curved silhouette.
d.rounded_rectangle((354,1130,1040,1670),radius=95,fill='#7ca88b')
d.rounded_rectangle((1008,1130,1694,1670),radius=95,fill='#7ca88b')
d.polygon([(400,1090),(600,1050),(1024,1170),(1024,1615),(660,1490),(400,1520)],fill='#fffdf5')
d.polygon([(1024,1170),(1448,1050),(1648,1090),(1648,1520),(1388,1490),(1024,1615)],fill='#fffdf5')
d.line([(1024,1180),(1024,1590)],fill='#e2cbbd',width=14)
for n in range(3):
    y=1250+n*85;d.line([(500,y),(850,y+42)],fill='#e6cfbd',width=15)
    d.line([(1190,y+42),(1548,y)],fill='#e6cfbd',width=15)
# Stem, leaves, five soft petals.
d.line([(1030,1170),(1030,820)],fill='#548a67',width=42)
d.ellipse((812,951,1037,1065),fill='#80aa82')
d.ellipse((1030,884,1270,1000),fill='#80aa82')
cx,cy=1024,685
for n in range(5):
    a=math.radians(n*72-90);x=cx+195*math.cos(a);y=cy+195*math.sin(a)
    d.ellipse((x-195,y-195,x+195,y+195),fill='#e989a0')
d.ellipse((864,525,1184,845),fill='#ffda87')
d.ellipse((945,638,969,668),fill='#7b4c45');d.ellipse((1079,638,1103,668),fill='#7b4c45')
d.arc((978,651,1070,722),0,180,fill='#7b4c45',width=12)
for x,y in [(508,610),(1562,810)]:
    d.line((x-35,y,x+35,y),fill='#e5b365',width=13);d.line((x,y-35,x,y+35),fill='#e5b365',width=13)
out=Path('App/Assets.xcassets/AppIcon.appiconset');out.mkdir(parents=True,exist_ok=True)
entries=[]
for pt,scale in [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)]:
    name=f'icon-{pt}@{scale}x.png';im.resize((pt*scale,pt*scale),Image.Resampling.LANCZOS).save(out/name)
    entries.append(dict(size=f'{pt}x{pt}',idiom='iphone',filename=name,scale=f'{scale}x'))
im.resize((1024,1024),Image.Resampling.LANCZOS).save(out/'icon-1024.png')
entries.append(dict(size='1024x1024',idiom='ios-marketing',filename='icon-1024.png',scale='1x'))
(out/'Contents.json').write_text(json.dumps(dict(images=entries,info=dict(version=1,author='xcode')),indent=2)+'\n')
Path('App/Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')

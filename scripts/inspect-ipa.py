"""Read-only, cross-platform verification of the downloaded exact IPA bytes."""
import argparse,hashlib,json,plistlib,struct,zipfile
from pathlib import Path,PurePosixPath

p=argparse.ArgumentParser();p.add_argument('ipa');p.add_argument('--report');a=p.parse_args()
path=Path(a.ipa)
with zipfile.ZipFile(path) as z:
    assert z.testzip() is None,'Corrupt ZIP member'
    assert all(not PurePosixPath(n).is_absolute() and '..' not in PurePosixPath(n).parts for n in z.namelist()),'Unsafe archive path'
    prefix='Payload/XinxinGarden.app/'
    info=plistlib.loads(z.read(prefix+'Info.plist'))
    assert info['CFBundleIdentifier']=='com.wm0104.xinxingarden'
    assert info['CFBundleDisplayName']=='欣语' and info['CFBundleShortVersionString']=='0.0.3'
    assert info['MinimumOSVersion']=='15.0'
    assert info['UIDeviceFamily']==[1],info.get('UIDeviceFamily')
    assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
    assert info['NSCalendarsUsageDescription'] and info['NSCalendarsFullAccessUsageDescription']
    forbidden=['NSLocationWhenInUseUsageDescription','NSContactsUsageDescription','NSMicrophoneUsageDescription','NSCameraUsageDescription','NSPhotoLibraryUsageDescription']
    assert all(k not in info for k in forbidden),'Unnecessary protected-resource description'
    assert z.read(prefix+'catalog.json') and z.read(prefix+'seed-resources.json')
    library=json.loads(z.read(prefix+'library.json'))
    assert len(library)>700 and any(r['id']=='curated-guide-7u-02' for r in library)
    exe=z.read(prefix+info['CFBundleExecutable'])
    magic,cpu,subtype,filetype,count,size,flags,reserved=struct.unpack_from('<8I',exe)
    assert magic==0xfeedfacf and cpu==0x0100000c,'Expected little-endian arm64 Mach-O'
    offset=32;minimum=None;platform=None;encrypted=False
    for _ in range(count):
        cmd,length=struct.unpack_from('<II',exe,offset)
        assert length>=8 and offset+length<=len(exe)
        if cmd==0x32:
            platform,minimum=struct.unpack_from('<II',exe,offset+8)
        if cmd==0x25:minimum=struct.unpack_from('<I',exe,offset+8)[0];platform=2
        if cmd==0x2c:encrypted=struct.unpack_from('<I',exe,offset+16)[0]!=0
        offset+=length
    assert platform==2 and minimum is not None,'Not a native iOS device executable'
    os_version=f'{minimum>>16}.{(minimum>>8)&255}.{minimum&255}'
    assert os_version=='15.0.0',os_version
    assert not encrypted,'Encrypted executable'
    assert prefix+'_CodeSignature/CodeResources' in z.namelist(),'Signature resources missing'
    catalog=json.loads(z.read(prefix+'catalog.json'))
    report=dict(ipa=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,bundleID=info['CFBundleIdentifier'],version=info['CFBundleShortVersionString'],minimumOS=info['MinimumOSVersion'],machOMinimumOS=os_version,architecture='arm64',deviceFamily=info['UIDeviceFamily'],books=len(catalog['books']),entries=sum(len(u['lessons']) for b in catalog['books'] for u in b['units']),zipIntegrity='passed',deviceTested=False)
    text=json.dumps(report,ensure_ascii=False,indent=2)
    print(text)
    if a.report:Path(a.report).write_text(text+'\n',encoding='utf-8')

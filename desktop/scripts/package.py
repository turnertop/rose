#!/usr/bin/env python3
"""Package a self-contained publish folder, with provenance and dependency licenses."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
version = ET.parse(root / 'Directory.Build.props').findtext('PropertyGroup/Version')
notices_only = sys.argv[1] == '--notices-only'
output = root if notices_only else Path(sys.argv[1]).resolve()
assets = json.loads((root / 'src/Rose.Desktop/obj/project.assets.json').read_text())
notices = ['Rose for Windows: third-party dependency information', '',
           'The following packages are included in the publish dependency graph.',
           'Platform-specific assets may be omitted from a particular binary distribution.',
           'Rose is licensed under Apache-2.0; see LICENSE.txt and NOTICE.txt.',
           'The dependencies below retain their respective licenses and notices.', '']
notices.extend(['MIT license terms (individual copyright notices follow):', '',
'''Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''', ''])
for key, library in sorted(assets['libraries'].items()):
    if library.get('type') != 'package':
        continue
    package = next((Path(folder) / library['path'] for folder in assets['packageFolders']
                    if (Path(folder) / library['path']).exists()), None)
    notices.append(key)
    if package:
        spec = next(package.glob('*.nuspec'), None)
        if spec:
            tree = ET.parse(spec)
            for element in tree.iter():
                local = element.tag.split('}')[-1]
                if local in ('license', 'copyright', 'projectUrl') and element.text:
                    notices.append(f'  {local}: {element.text}')
                if local == 'license' and element.get('type') == 'file' and element.text:
                    license_file = package / element.text
                    if license_file.is_file():
                        notices.append(license_file.read_text(errors='replace'))
        for file in package.iterdir():
            if file.is_file() and file.name.lower() in ('license', 'license.txt', 'license.md', 'third-party-notices.txt', 'third-party-notices.md', 'thirdpartynotices.txt'):
                notices.append(file.read_text(errors='replace'))
    notices.append('')
(output / 'THIRD-PARTY-NOTICES.txt').write_text('\n'.join(line.rstrip() for line in '\n'.join(notices).splitlines()).rstrip() + '\n')
if notices_only:
    print(output / 'THIRD-PARTY-NOTICES.txt')
    sys.exit(0)
for filename in ('LICENSE', 'NOTICE'):
    shutil.copyfile(root.parent / filename, output / (filename + '.txt'))
architecture = output.name.rsplit('-', 1)[-1]
expected_machine = {'x64': 0x8664, 'arm64': 0xAA64}[architecture]
for filename in ('Rose.exe', 'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'libSkiaSharp.dll', 'libHarfBuzzSharp.dll', 'av_libglesv2.dll'):
    path = output / filename
    data = path.read_bytes()
    assert data[:2] == b'MZ', f'{filename} is not a Windows binary'
    offset = struct.unpack_from('<I', data, 60)[0]
    assert data[offset:offset + 4] == b'PE\0\0', f'{filename} has no PE signature'
    machine = struct.unpack_from('<H', data, offset + 4)[0]
    assert machine == expected_machine, f'{filename} targets {machine:x}, expected {architecture}'
for filename in ('Rose.dll', 'Rose.Core.dll', 'Rose.Imaging.dll', 'Avalonia.Win32.dll', 'System.Drawing.Common.dll'):
    assert (output / filename).is_file(), f'Missing dependency: {filename}'
runtime_config = json.loads((output / 'Rose.runtimeconfig.json').read_text())
assert runtime_config['runtimeOptions'].get('includedFrameworks'), 'The package must include .NET rather than require installation'
# The self-contained .NET runtime is an SDK download dependency, not necessarily
# a library entry in project.assets.json. Include its notices as well.
runtime_version = next(element.text for element in ET.parse(root / 'src/Rose.Desktop/Rose.Desktop.csproj').iter()
                       if element.tag == 'RuntimeFrameworkVersion')
for package_folder in assets['packageFolders']:
    runtime = Path(package_folder) / f'microsoft.netcore.app.runtime.win-{architecture}' / runtime_version
    if runtime.exists():
        with (output / 'THIRD-PARTY-NOTICES.txt').open('a') as destination:
            for file in runtime.iterdir():
                if file.is_file() and ('license' in file.name.lower() or 'notice' in file.name.lower()):
                    destination.write(f'\n.NET runtime {runtime_version} / {file.name}\n')
                    destination.write(file.read_text(errors='replace'))
        break
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip())
manifest = {'product': 'Rose for Windows', 'version': f'{version}-preview', 'sourceCommit': commit,
            'sourceDirty': dirty, 'selfContained': True,
            'files': {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'build-manifest.json'}}
(output / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
archive = output.with_name(output.name + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in sorted(output.rglob('*')):
        if path.is_file():
            z.write(path, str(Path(output.name) / path.relative_to(output)))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None, 'Archive CRC verification failed'
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
print(f'Created {archive} ({archive.stat().st_size / 1048576:.1f} MiB)\nSHA256 {digest}')

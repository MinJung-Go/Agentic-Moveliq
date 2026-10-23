#!/usr/bin/env python3
"""Embed local preview styles/assets so IDE HTML previews need no file resolver.

Edit design.css / design.conversations.css, then run this script to refresh all
HTML exports. These inline style blocks are generated, not independent themes.
"""
from pathlib import Path
import base64
import re

ROOT = Path(__file__).resolve().parent
MILO = ROOT.parent.parent / 'AgenticKeepKeep/Resources/Assets.xcassets/Milo.imageset/milo.png'
MILO_RELATIVE = '../../AgenticKeepKeep/Resources/Assets.xcassets/Milo.imageset/milo.png'
STYLES = {
    'design.html': ['design.css', 'design.conversations.css'],
    'design.conversations.html': ['design.css', 'design.conversations.css'],
    'design.colors.html': ['design.css'],
}

for name, sheets in STYLES.items():
    target = ROOT / name
    html = target.read_text()
    for sheet in sheets:
        block = f'<style data-preview-source="{sheet}">\n{(ROOT / sheet).read_text()}\n</style>'
        pattern = rf'<style data-preview-source="{re.escape(sheet)}">[\s\S]*?</style>'
        if re.search(pattern, html):
            html = re.sub(pattern, lambda _: block, html)
        else:
            old = f'<link rel="stylesheet" href="{sheet}">'
            if old not in html:
                raise RuntimeError(f'{name}: missing style source {sheet}')
            html = html.replace(old, block)
    # The marker lets later runs refresh the embedded asset from its source.
    html = html.replace(f'src="{MILO_RELATIVE}"', 'data-embedded-asset="milo" src=""')
    if 'data-embedded-asset="milo"' in html:
        uri = 'data:image/png;base64,' + base64.b64encode(MILO.read_bytes()).decode('ascii')
        html = re.sub(r'data-embedded-asset="milo" src="[^"]*"',
                      lambda _: f'data-embedded-asset="milo" src="{uri}"', html)
    # Explicit icon dimensions also protect static previews from default SVG sizing.
    html = html.replace('<svg viewBox="', '<svg width="24" height="24" viewBox="')
    html = html.replace(r'<svg viewBox=\"', r'<svg width=\"24\" height=\"24\" viewBox=\"')
    target.write_text(html)
    print(f'{name}: standalone styles and assets refreshed')

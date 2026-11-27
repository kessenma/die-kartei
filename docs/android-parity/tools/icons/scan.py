import re, os, json, glob, collections, sys
W = '/Users/ke/.hermes/cache/scratch/parity-audit/icon-work/'
syms = set(json.load(open(W + 'sf_names.json')))
ROOT = '/Users/ke/ws/die-kartei'
roots = [ROOT + '/german-ai-flashcards', ROOT + '/KeyboardExtension']
files = [p for r in roots for p in glob.glob(r + '/**/*.swift', recursive=True) if '/.build/' not in p]
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')
ctxre = re.compile(r'systemName|systemImage|symbol|icon|Icon|Image\(|Label\(|glyph', re.I)
hits = []
for p in files:
    src = open(p, encoding='utf-8', errors='ignore').read()
    lines = src.split('\n')
    # file-level platform guess
    head = '\n'.join(l for l in lines[:40] if l.strip())
    macfile = ('/Mac' in p) or bool(re.search(r'^#if os\(macOS\)', head, re.M) and not re.search(r'^#if os\(iOS\)', head, re.M))
    stack = []  # track #if os() blocks
    for i, l in enumerate(lines):
        s = l.strip()
        m = re.match(r'#if\s+(.*)', s)
        if m: stack.append(m.group(1)); 
        elif s.startswith('#else') and stack: stack[-1] = 'NOT(' + stack[-1] + ')'
        elif s.startswith('#endif') and stack: stack.pop()
        if s.startswith('//'): continue
        for mm in lit.finditer(l):
            v = mm.group(1)
            if v in syms:
                plat = 'all'
                cond = ' '.join(stack)
                if macfile or re.search(r'(?<!NOT\()os\(macOS\)', cond) or ('NOT(os(iOS)' in cond): plat = 'mac'
                elif re.search(r'(?<!NOT\()os\(iOS\)', cond) or 'canImport(UIKit)' in cond or 'NOT(os(macOS)' in cond: plat = 'ios'
                if '/KeyboardExtension/' in p: plat = 'ios-keyboard'
                hits.append(dict(file=os.path.relpath(p, ROOT), line=i + 1, name=v, src=s, plat=plat))

def accept_und(h):
    n = re.escape(h['name']); s = h['src']
    pats = [r'(case [^:"]+|default)\s*:\s*\(?\s*"%s"' % n, r'return \(?"%s"' % n, r'^"%s",?$' % n,
            r'\?\s*"[^"]+"\s*:\s*"%s"' % n, r':\s*"%s"\)' % n,
            r'(summaryStat|ActivityRow|sourceRow|shareLink|row|note|add|point|pickerRow|chooserRow)\(.*"%s"\s*(\)|,\s*id:|,$)' % n,
            r'^: "%s"\)?$' % n, r'^return "%s"$' % n]
    return any(re.search(p, s) for p in pats)

FORCE_OK = {('ipad',), ('iphone',), ('laptopcomputer',), ('equal',)}
def keep(h):
    s = h['src']; n = h['name']
    bad = ['english:', 'englishTranslation', 'en: ', 'noteVocabEncounters', 'source: "photo"', 'replacingOccurrences', 'KasusService.swift']
    if any(b in s for b in bad) or 'KasusService.swift' in h['file'] or 'SyncDebugVerify' in h['file']:
        return False
    if 'KasusStoryView.swift' in h['file'] and n == 'table': return False
    if ctxre.search(s): return True
    if '.' in n: return True
    if n in ('ipad', 'iphone', 'laptopcomputer', 'equal'): return True
    if 'SchreibblattStats' in h['file'] and n in ('clock', 'star'): return True
    return accept_und(h)

kept = [h for h in hits if keep(h)]
# extra: names newer than this macOS's CoreGlyphs list
for p in files:
    for i, l in enumerate(open(p, encoding='utf-8', errors='ignore')):
        for m in re.finditer(r'"(link\.badge\.minus)"', l):
            kept.append(dict(file=os.path.relpath(p, ROOT), line=i + 1, name=m.group(1), src=l.strip(), plat='all'))
# What's New feed (JSON resource rendered with Image(systemName:))
wn = ROOT + '/german-ai-flashcards/Resources/whats_new.json'
for i, l in enumerate(open(wn, encoding='utf-8')):
    for m in re.finditer(r'"(?:icon|symbol|systemImage)"\s*:\s*"([^"]+)"', l):
        kept.append(dict(file=os.path.relpath(wn, ROOT), line=i + 1, name=m.group(1), src=l.strip(), plat='all'))

def feature(h):
    f = h['file']
    if f.startswith('KeyboardExtension/'): return 'Keyboard extension'
    parts = f.split('/')[1:]
    if parts[0] == 'Features' and len(parts) > 2: return parts[1]
    if parts[0] == 'Features': return parts[1].replace('.swift', '')
    if parts[0] == 'Resources': return 'WhatsNew'
    stem = parts[-1].replace('.swift', '')
    return parts[0] + ':' + stem
for h in kept: h['feature'] = feature(h)
json.dump(kept, open(W + 'hits.json', 'w'), indent=0, ensure_ascii=False)
print(len(hits), len(kept), len(set(h['name'] for h in kept)))

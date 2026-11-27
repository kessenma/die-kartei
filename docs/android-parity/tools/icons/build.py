import json, re, csv, collections, sys
sys.path.insert(0, '.')
import importlib, mapping; importlib.reload(mapping)
from mapping import M, lookup
W = '/Users/ke/.hermes/cache/scratch/parity-audit/'
h = json.load(open('hits.json'))

# SkipUI fallback table
img = open('/Users/ke/ws/die-kartei-android/DieKarteiAndroid/.build/checkouts/skip-ui/Sources/SkipUI/SkipUI/Components/Image.swift').read()
skip = dict(re.findall(r'(?m)^\s*case "([^"]+)": return "(Icons\.[A-Za-z]+\.[A-Za-z]+)"', img))

STEM = {
 'ConversationConfig': 'Conversation', 'JobPosting': 'JobPrep', 'BatchJob': 'Queue', 'SpielKind': 'Spiele',
 'GermanWriter': 'Schreiben', 'SavedDeck': 'Cards', 'ValidationResult': 'Cards', 'ClassMaterial': 'ClassNotes',
 'ClassCourse': 'ClassNotes', 'StudyPaper': 'ClassNotes', 'JournalEntry': 'ClassNotes', 'HoerenNumberKind': 'Hoeren',
 'HoerenRound': 'Hoeren', 'WordArtStyle': 'Zeichnen', 'ImageGenModel+Descriptors': 'Zeichnen',
 'SchreibblattStats': 'Schreibblatt', 'SchreibblattLayout': 'Schreibblatt', 'AchievementService': 'Progress',
 'JourneyService': 'Progress', 'CelebrationCenter': 'Progress', 'PyramidLayer': 'Progress', 'PlacementAttempt': 'Progress',
 'TodayPlanner': 'Home', 'MemoryEventStore': 'Settings', 'SyncProgress': 'Settings', 'ModelConfiguration': 'Settings',
 'WhatsNewService': 'WhatsNew', 'NavBar': 'TabBar', 'ContentView': 'TabBar',
}
def feat(x):
    f = x['file']; ft = x['feature']
    if '/Shared/Pencil/' in f: return 'Pencil'
    if f.split('/')[-1].startswith('Mac'): return 'Mac shell'
    if ':' in ft:
        kind, stem = ft.split(':', 1)
        if stem in STEM: return STEM[stem]
        if stem.startswith(('Kasus', 'Grammar', 'Reflexiv')): return 'Grammar'
        return stem
    if ft.startswith(('Model', 'ImageModel')): return 'Model UI'
    return ft
APPLE_ONLY = {'Pencil': 'PencilKit', 'Mac shell': 'macOS', 'Keyboard extension': 'iOS keyboard ext'}

by = collections.defaultdict(list)
for x in h:
    x['feat'] = feat(x)
    if 'ICloudSync' in x['file'] or 'MacWritingHelper' in x['file']:
        x['apple'] = 'iCloud/Mac helper'
    else:
        x['apple'] = APPLE_ONLY.get(x['feat']) or ({'mac': 'macOS', 'ios-keyboard': 'iOS keyboard ext'}.get(x['plat']))
    by[x['name']].append(x)

ALTQ = {k: 'exact' for k in [
    'rectangle.stack', 'cube.transparent', 'character.book.closed', 'character.bubble', 'circle.dashed', 'circle.dotted',
    'a.circle', 'a.square', 'd.circle', 'e.circle', 'sparkle', 'star.slash', 'die.face.3', 'exclamationmark.magnifyingglass',
    'text.cursor', 'text.viewfinder', 'circle.grid.3x3.fill', 'moon.stars', 'testtube.2', 'lasso', 'arrow.up.forward.circle.fill',
    'chevron.left.circle.fill', 'chevron.right.circle.fill', 'metronome', 'tortoise', 'square.stack.3d.up', 'books.vertical',
    'hammer', 'paintbrush.pointed', 'cpu', 'ear', 'brain']}
ALTQ.pop('books.vertical')
ALTQ.update({'pyramid.fill': 'close (outline only)', 'number.circle': 'concept', 'questionmark.square.dashed': 'concept'})
rows = []
for n in sorted(by, key=lambda k: (-len(by[k]), k)):
    xs = by[n]
    (ms, q, alt, note), filled = lookup(n)
    fc = collections.Counter(x['feat'] for x in xs)
    feats = '; '.join(f'{k}({v})' for k, v in fc.most_common())
    fill = filled or n.endswith('.fill') or '.fill.' in n
    style = ('Rounded' + (' FILL1' if fill else '')) if ms else ''
    lib, an = (alt.split(':') if alt else ('', ''))
    lib = {'phosphor': 'Phosphor (MIT)', 'lucide': 'Lucide (ISC)', 'tabler': 'Tabler (MIT)'}.get(lib, '')
    notes = note
    base = n[:-5] if n.endswith('.fill') and n not in ALTQ else n
    if alt:
        notes = f"alt match={ALTQ.get(base, 'close')}" + ('; ' + notes if notes else '')
    apple = {x['apple'] for x in xs}
    if None not in apple:
        notes = (f"apple-only use ({', '.join(sorted(apple))})" + ('; ' + notes if notes else ''))
    sm = skip.get(n, '')
    if sm and ms:
        # flag when SkipUI's fallback differs in shape from the chosen symbol
        pass
    rows.append(dict(sf_symbol=n, uses=len(xs), features=feats, skipui_mapped=sm, material_symbol=ms,
                     material_style=style, match_quality=q, alternate_library=lib, alternate_name=an, notes=notes))

with open(W + 'icon-map.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

# stats
tot = sum(r['uses'] for r in rows)
print('distinct', len(rows), 'uses', tot)
qc = collections.Counter(r['match_quality'] for r in rows); print('quality', qc)
qu = collections.Counter();
for r in rows: qu[r['match_quality']] += r['uses']
print('quality by uses', qu)
print('skipui mapped', sum(1 for r in rows if r['skipui_mapped']), 'uses', sum(r['uses'] for r in rows if r['skipui_mapped']))
print('fill variants', sum(1 for r in rows if 'FILL1' in r['material_style'] or r['sf_symbol'].endswith('.fill')))
print('alt used', collections.Counter(r['alternate_library'] for r in rows if r['alternate_library']))
ao = [r for r in rows if r['notes'].startswith('apple-only')]
print('apple-only symbols', len(ao), [r['sf_symbol'] for r in ao])
fu = collections.Counter(); fs = collections.defaultdict(set)
for x in h: fu[x['feat']] += 1; fs[x['feat']].add(x['name'])
print('features', [(k, v, len(fs[k])) for k, v in fu.most_common()])
print('top30', [(r['sf_symbol'], r['uses']) for r in rows[:30]])
print('weak', [(r['sf_symbol'], r['uses'], r['match_quality']) for r in rows if r['match_quality'] in ('concept', 'none')])
json.dump(rows, open('rows.json', 'w'))
rank = {'exact': 0, 'close': 1, 'concept': 2, 'none': 3}
def best(r):
    q = rank[r['match_quality']]
    m = re.match(r'alt match=(\w+)', r['notes'])
    if m: q = min(q, rank.get(m.group(1), 1))
    return q
bc = collections.Counter(); bu = collections.Counter()
for r in rows:
    b = best(r); bc[b] += 1; bu[b] += r['uses']
print('best-of distinct', {k: bc[v] for k, v in rank.items()}, 'uses', {k: bu[v] for k, v in rank.items()})
print('still weak after alternates', [(r['sf_symbol'], r['uses']) for r in rows if best(r) >= 2])

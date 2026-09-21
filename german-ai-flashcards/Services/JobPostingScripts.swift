import Foundation

/// JavaScript the job-posting clipper runs inside its web view.
///
/// Three scripts: `observer` is installed once as a user script and reports selection changes and
/// DOM settling; `analyze` is evaluated on demand and returns a `JobPageAnalysis` as JSON;
/// `readSelection` / `clearSelection` are the on-demand fallbacks when a page swallows
/// `selectionchange`. Everything is wrapped so a hostile page can't throw into Swift.
enum JobPostingScripts {
    /// Message handler names the observer posts to.
    static let selectionHandler = "dkSelection"
    static let pageHandler = "dkPage"
    static let handlerNames = [selectionHandler, pageHandler]

    /// Installed at document end in every frame. Posts the trimmed selection (debounced 250 ms)
    /// and "settled" once the DOM has been quiet for 800 ms, which is how single-page job boards
    /// announce that the posting has actually rendered.
    static let observer = #"""
    (function () {
      if (window.__dkObs) { return; }
      window.__dkObs = true;
      function post(name, body) {
        try { window.webkit.messageHandlers[name].postMessage(body); } catch (e) {}
      }
      var selTimer = null;
      document.addEventListener('selectionchange', function () {
        if (selTimer) { clearTimeout(selTimer); }
        selTimer = setTimeout(function () {
          var s = '';
          try { s = String(window.getSelection ? window.getSelection().toString() : ''); } catch (e) {}
          post('dkSelection', s.trim().slice(0, 20000));
        }, 250);
      });
      var mutTimer = null;
      try {
        new MutationObserver(function () {
          if (mutTimer) { clearTimeout(mutTimer); }
          mutTimer = setTimeout(function () { post('dkPage', 'settled'); }, 800);
        }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
      } catch (e) {}
    })();
    """#

    /// Returns `JSON.stringify({ sections, meta })`.
    ///
    /// Sections: every visible heading outside navigation, footers, dialogs, and cookie/consent
    /// containers, with the text that follows it up to the next heading. A heading wrapped alone
    /// in its own element (common on component-built pages) is resolved by stepping up one level
    /// and reading that element's siblings instead. Bold lines count as headings only when the
    /// bold text is the whole line. Sections are scored by German and English job-posting
    /// vocabulary, deduplicated against wrappers that contain other sections, and capped at 12.
    ///
    /// Meta: JSON-LD `JobPosting` first, then `og:site_name`, then the document title's trailing
    /// segment for the company; a labelled "Standort:" style line or a pin line for the location.
    static let analyze = #"""
    (function () {
      var EXCL_SEL = 'nav, header, footer, aside, [role=dialog], [aria-modal=true], [role=navigation], [role=banner], [role=contentinfo]';
      var EXCL_RE = /cookie|consent|\bcmp\b|gdpr|onetrust|usercentrics|banner|similar|related|recommend|ähnlich|aehnlich/i;
      var NOISE_TITLE = /ähnliche|aehnliche|similar|weitere (jobs|stellen)|more jobs|other (positions|jobs)|related|rechtliches|impressum|datenschutz/i;
      var TIERS = [
        [5, /aufgaben|erwartet (dich|sie)|deine rolle|ihre rolle|tätigkeit|taetigkeit|responsibilit|what you.ll do|your role|about the role|\btasks\b/i],
        [5, /profil|anforderung|qualifikation|voraussetzung|bringst du mit|bringen sie mit|requirement|qualification|what you bring|who you are|about you|\bskills\b/i],
        [4, /wir bieten|bieten wir|benefit|vorteile|what we offer|why us|perks/i],
        [4, /stellenbeschreibung|beschreibung|die stelle|job description|description/i],
        [2, /über uns|ueber uns|das sind wir|unternehmen|about us|who we are|company/i],
        [1, /bewerbung|dein weg|so geht|how to apply|application|kontakt|contact/i]
      ];
      var HEADING_SEL = 'h1, h2, h3, h4, [role=heading]';

      function txt(el) {
        var t = el && el.innerText ? el.innerText : '';
        return String(t).replace(/\u00a0/g, ' ').trim();
      }
      function visible(el) {
        try { return el.getClientRects().length > 0; } catch (e) { return true; }
      }
      function excluded(el) {
        for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
          try { if (n.matches(EXCL_SEL)) { return true; } } catch (e) {}
          var idc = (n.id || '') + ' ' + (typeof n.className === 'string' ? n.className : '');
          if (EXCL_RE.test(idc)) { return true; }
        }
        return false;
      }
      function isHeadingTag(el) {
        return /^H[1-4]$/.test(el.tagName) || el.getAttribute('role') === 'heading';
      }
      function isHeading(el) {
        if (isHeadingTag(el)) { return true; }
        if (/^(STRONG|B)$/.test(el.tagName)) {
          var t = txt(el);
          if (!t || t.length >= 60) { return false; }
          var p = el.parentElement;
          return !!p && txt(p) === t;
        }
        return false;
      }
      function containsHeading(node) {
        if (isHeading(node)) { return true; }
        try { return !!node.querySelector(HEADING_SEL); } catch (e) { return false; }
      }
      function isRoot(node) {
        return !node || node === document.body || node === document.documentElement ||
          node.tagName === 'MAIN' || node.tagName === 'ARTICLE';
      }
      // The element that wraps a heading and its section: climb through wrappers that hold
      // nothing but the heading itself.
      function sectionRoot(h) {
        var node = h;
        var t = txt(h);
        while (node.parentElement && !isRoot(node.parentElement) && txt(node.parentElement) === t) {
          node = node.parentElement;
        }
        return node.parentElement || node;
      }
      // The text after a heading and the elements it came from, so the page can be asked to
      // tint exactly those elements when the section is selected.
      function sectionText(h) {
        var node = h;
        for (var level = 0; level < 3 && node; level++) {
          var parts = [];
          var nodes = [];
          var sib = node.nextElementSibling;
          while (sib) {
            if (containsHeading(sib)) { break; }
            if (visible(sib) && !excluded(sib)) {
              var t = txt(sib);
              if (t) { parts.push(t); nodes.push(sib); }
            }
            sib = sib.nextElementSibling;
          }
          var joined = parts.join('\n').trim();
          if (joined) { return { text: joined, nodes: nodes }; }
          if (isRoot(node.parentElement)) { break; }
          node = node.parentElement;
        }
        return { text: '', nodes: [] };
      }
      function score(heading) {
        for (var i = 0; i < TIERS.length; i++) {
          if (TIERS[i][1].test(heading)) { return TIERS[i][0]; }
        }
        return 0;
      }

      // Markers from the previous analysis; the kept sections are re-marked below.
      var stale = document.querySelectorAll('[data-dk-sec]');
      for (var s0 = 0; s0 < stale.length; s0++) {
        stale[s0].removeAttribute('data-dk-sec');
        stale[s0].removeAttribute('data-dk-on');
      }

      var candidates = document.querySelectorAll(HEADING_SEL + ', strong, b');
      var heads = [];
      var noiseRoots = [];
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (!isHeading(el) || !visible(el) || excluded(el)) { continue; }
        var title = txt(el);
        if (!title || title.length > 80) { continue; }
        if (NOISE_TITLE.test(title)) { noiseRoots.push(sectionRoot(el)); continue; }
        heads.push(el);
      }
      function inNoise(el) {
        for (var i = 0; i < noiseRoots.length; i++) {
          try { if (noiseRoots[i] !== document.body && noiseRoots[i].contains(el)) { return true; } } catch (e) {}
        }
        return false;
      }

      var secs = [];
      for (var j = 0; j < heads.length; j++) {
        var h = heads[j];
        if (inNoise(h)) { continue; }
        var found = sectionText(h);
        if (found.text.length < 80) { continue; }
        secs.push({
          heading: txt(h), text: found.text.slice(0, 6000), score: score(txt(h)), order: j,
          nodes: [h].concat(found.nodes), drop: false
        });
      }
      for (var a = 0; a < secs.length; a++) {
        for (var c = 0; c < secs.length; c++) {
          if (a === c) { continue; }
          // A wrapper whose text contains another section's text is the outer duplicate.
          if (secs[a].text.length > secs[c].text.length && secs[a].text.indexOf(secs[c].text) >= 0) {
            secs[a].drop = true;
            break;
          }
          // The same block repeated on the page (a call to action shown twice): keep the first.
          if (c < a && secs[a].heading === secs[c].heading && secs[a].text === secs[c].text) {
            secs[a].drop = true;
            break;
          }
        }
      }
      var out = secs.filter(function (s) { return !s.drop; });
      out.sort(function (x, y) { return (y.score - x.score) || (x.order - y.order); });
      out = out.slice(0, 12);
      // Tag the kept sections' elements by order, after the dedupe, so a dropped wrapper never
      // overwrites a kept section's marker. Attribute changes don't wake the settle observer.
      for (var m0 = 0; m0 < out.length; m0++) {
        var ns = out[m0].nodes;
        for (var n0 = 0; n0 < ns.length; n0++) {
          try { ns[n0].setAttribute('data-dk-sec', String(out[m0].order)); } catch (e) {}
        }
      }
      out = out.map(function (s) {
        return { heading: s.heading, text: s.text, score: s.score, order: s.order };
      });

      // Meta
      function ldJobPosting() {
        var scripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (var i = 0; i < scripts.length; i++) {
          var data;
          try { data = JSON.parse(scripts[i].textContent); } catch (e) { continue; }
          var items = [];
          (function flat(d) {
            if (!d) { return; }
            if (Array.isArray(d)) { d.forEach(flat); return; }
            if (typeof d === 'object') { items.push(d); if (d['@graph']) { flat(d['@graph']); } }
          })(data);
          for (var k = 0; k < items.length; k++) {
            var t = items[k]['@type'];
            if (t === 'JobPosting' || (Array.isArray(t) && t.indexOf('JobPosting') >= 0)) { return items[k]; }
          }
        }
        return null;
      }
      var company = '', location = '', ldTitle = '';
      var ld = ldJobPosting();
      if (ld) {
        ldTitle = String(ld.title || '');
        var org = ld.hiringOrganization; if (Array.isArray(org)) { org = org[0]; }
        if (org && org.name) { company = String(org.name); }
        var loc = ld.jobLocation; if (Array.isArray(loc)) { loc = loc[0]; }
        var addr = loc && loc.address; if (Array.isArray(addr)) { addr = addr[0]; }
        if (typeof addr === 'string') { location = addr; }
        else if (addr) { location = [addr.addressLocality, addr.addressRegion].filter(Boolean).join(', '); }
      }
      if (!company) {
        var og = document.querySelector('meta[property="og:site_name"]');
        if (og && og.content) { company = og.content.trim(); }
      }
      var docTitle = String(document.title || '');
      if (!company) {
        var parts = docTitle.split(/\s+[-|–—·:]\s+/).map(function (s) { return s.trim(); }).filter(Boolean);
        var JOBBY = /m\/w\/d|w\/m\/d|\(m\/w\)|\bjob\b|stelle|karriere|career|vacanc/i;
        if (parts.length > 1) {
          var last = parts[parts.length - 1], first = parts[0];
          if (last.length < 40 && !JOBBY.test(last)) { company = last; }
          else if (first.length < 40 && !JOBBY.test(first) && first !== last) { company = first; }
        }
      }
      if (!location) {
        var root = document.querySelector('main') || document.querySelector('article') || document.body;
        var LOC_RE = /^(Standort|Arbeitsort|Einsatzort|Dienstort|Ort|Location|Job location|Arbeitsplatz)\s*[:：]?\s*(.{2,60})$/i;
        var PIN_RE = /^📍\s*(.{2,60})$/;
        var blocks = root.querySelectorAll('p, li, div, span, dd, td');
        for (var b = 0; b < blocks.length && !location; b++) {
          var bl = blocks[b];
          if (bl.children.length > 3 || !visible(bl) || excluded(bl) || inNoise(bl)) { continue; }
          var lines = txt(bl).split('\n');
          for (var l = 0; l < lines.length; l++) {
            var line = lines[l].trim();
            var m = LOC_RE.exec(line);
            if (m) { location = m[2].trim(); break; }
            m = PIN_RE.exec(line);
            if (m) { location = m[1].trim(); break; }
          }
        }
      }
      var h1El = null;
      var h1s = document.querySelectorAll('h1');
      for (var q = 0; q < h1s.length; q++) { if (visible(h1s[q]) && txt(h1s[q])) { h1El = h1s[q]; break; } }
      var h1 = h1El ? txt(h1El) : ldTitle;

      return JSON.stringify({
        sections: out,
        meta: { title: docTitle, h1: h1.slice(0, 200), company: company.slice(0, 120), location: location.slice(0, 120) }
      });
    })()
    """#

    /// Tint the elements of the sections with these `order`s (as tagged by `analyze`) and untint
    /// every other tagged element. `rgb` is "r, g, b" for the tint; the style is installed once.
    static func highlight(orders: [Int], rgb: String) -> String {
        let list = orders.map(String.init).joined(separator: ", ")
        return """
        (function () {
          var on = [\(list)];
          var style = document.getElementById('dk-hl-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'dk-hl-style';
            style.textContent = '[data-dk-on] { background-color: rgba(\(rgb), 0.24) !important; box-shadow: 0 0 0 6px rgba(\(rgb), 0.24); border-radius: 4px; }';
            (document.head || document.documentElement).appendChild(style);
          }
          var all = document.querySelectorAll('[data-dk-sec]');
          for (var i = 0; i < all.length; i++) {
            var o = parseInt(all[i].getAttribute('data-dk-sec'), 10);
            if (on.indexOf(o) >= 0) { all[i].setAttribute('data-dk-on', '1'); } else { all[i].removeAttribute('data-dk-on'); }
          }
          return '';
        })()
        """
    }

    /// Scroll the page so the section's heading sits at the top of the visible part, above the
    /// panel. The heading is the first element tagged with the section's order.
    static func scrollTo(order: Int) -> String {
        """
        (function () {
          var el = document.querySelector('[data-dk-sec="\(order)"]');
          if (el && el.scrollIntoView) {
            el.style.scrollMarginTop = '12px';
            el.scrollIntoView({ block: 'start', behavior: 'smooth' });
          }
          return '';
        })()
        """
    }

    /// Returns `JSON.stringify({ present })`: whether a cookie / consent notice is pinned to the
    /// bottom of the viewport, where the collapsed capture panel sits.
    ///
    /// Asks what is actually under that strip (`elementsFromPoint` at a few points along the
    /// bottom), climbs to the nearest fixed or sticky ancestor, and counts it only when it reads
    /// like a consent notice and offers a button. Sticky "apply now" bars on job boards are
    /// deliberately not matched: they never go away, and the panel would never come back.
    static let consentOverlay = #"""
    (function () {
      var CONSENT = /cookie|consent|datenschutz|privacy|zustimm|einwillig|akzeptier|accept|agree|tracking|cmp|gdpr|dsgvo/i;
      var h = window.innerHeight, w = window.innerWidth;
      if (!h || !w || !document.elementsFromPoint) { return JSON.stringify({ present: false }); }
      function pinned(el) {
        for (var n = el; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
          var pos = '';
          try { pos = getComputedStyle(n).position; } catch (e) {}
          if (pos === 'fixed' || pos === 'sticky') {
            var r = n.getBoundingClientRect();
            if (r.height > 0 && r.height < h * 0.85 && r.bottom >= h - 12) { return n; }
          }
        }
        return null;
      }
      function consentish(n) {
        var idc = (n.id || '') + ' ' + (typeof n.className === 'string' ? n.className : '');
        var text = String(n.innerText || '').slice(0, 2000);
        if (!CONSENT.test(idc) && !CONSENT.test(text)) { return false; }
        try { return !!n.querySelector('button, [role=button], input[type=button], input[type=submit], a'); } catch (e) { return false; }
      }
      var ys = [h - 20, h - 60, h - 100];
      var xs = [w * 0.15, w * 0.5, w * 0.85];
      for (var i = 0; i < ys.length; i++) {
        for (var j = 0; j < xs.length; j++) {
          var stack;
          try { stack = document.elementsFromPoint(xs[j], ys[i]); } catch (e) { continue; }
          for (var k = 0; k < stack.length; k++) {
            var el = pinned(stack[k]);
            if (el && consentish(el)) { return JSON.stringify({ present: true }); }
          }
        }
      }
      return JSON.stringify({ present: false });
    })()
    """#

    /// The current selection as a string, for the manual "Read selection" fallback.
    static let readSelection = #"""
    (function () {
      try { return String(window.getSelection ? window.getSelection().toString() : ''); } catch (e) { return ''; }
    })()
    """#

    /// Drops the page selection after it has been added, so the next highlight starts clean.
    static let clearSelection = #"""
    (function () {
      try { if (window.getSelection) { window.getSelection().removeAllRanges(); } } catch (e) {}
      return '';
    })()
    """#
}

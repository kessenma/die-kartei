import Foundation

/// JavaScript the job-posting reader runs inside its live-page surface.
///
/// `reader` is installed once as a user script: it reports selection changes the way the clipper's
/// observer does, and turns a double tap on a word into a `dkWordTap` message. `decorate` is
/// evaluated on demand and marks saved and looked-up words on the page with the CSS Custom
/// Highlight API (a `<mark>` fallback when the page's WebKit lacks it). Everything is wrapped so a
/// hostile page can't throw into Swift.
enum JobReadingScripts {
    static let selectionHandler = JobPostingScripts.selectionHandler
    static let wordTapHandler = "dkWordTap"
    static let handlerNames = [selectionHandler, wordTapHandler]

    /// Installed at document end in every frame.
    ///
    /// The double tap is detected from `touchend` pairs (within 300 ms and 20 px) rather than
    /// `dblclick`, which WebKit doesn't deliver reliably on touch. The second tap is
    /// `preventDefault`ed so it doesn't also become a click; double-tap-to-zoom is switched off
    /// separately with `touch-action: manipulation` on the root, which keeps pinch zoom.
    static let reader = #"""
    (function () {
      if (window.__dkReader) { return; }
      window.__dkReader = true;
      function post(name, body) {
        try { window.webkit.messageHandlers[name].postMessage(body); } catch (e) {}
      }
      try {
        var s = document.createElement('style');
        s.id = 'dk-reader-touch';
        s.textContent = 'html { touch-action: manipulation; }';
        (document.head || document.documentElement).appendChild(s);
      } catch (e) {}

      var selTimer = null;
      document.addEventListener('selectionchange', function () {
        if (selTimer) { clearTimeout(selTimer); }
        selTimer = setTimeout(function () {
          var t = '';
          try { t = String(window.getSelection ? window.getSelection().toString() : ''); } catch (e) {}
          post('dkSelection', t.trim().slice(0, 20000));
        }, 250);
      });

      var WORD = /[\p{L}\p{M}][\p{L}\p{M}\-'’]*/gu;
      function wordAt(x, y) {
        var range = null;
        try {
          if (document.caretRangeFromPoint) {
            range = document.caretRangeFromPoint(x, y);
          } else if (document.caretPositionFromPoint) {
            var p = document.caretPositionFromPoint(x, y);
            if (p) { range = document.createRange(); range.setStart(p.offsetNode, p.offset); }
          }
        } catch (e) {}
        if (!range) { return ''; }
        var node = range.startContainer;
        if (!node || node.nodeType !== 3) { return ''; }
        var text = node.textContent || '';
        var off = range.startOffset;
        var m;
        WORD.lastIndex = 0;
        while ((m = WORD.exec(text)) !== null) {
          if (m.index <= off && off <= m.index + m[0].length) { return m[0]; }
          if (m.index > off) { break; }
        }
        return '';
      }

      var lastTap = 0, lastX = 0, lastY = 0;
      document.addEventListener('touchend', function (ev) {
        var t = ev.changedTouches && ev.changedTouches[0];
        if (!t) { return; }
        var now = Date.now();
        if (now - lastTap < 300 && Math.abs(t.clientX - lastX) < 20 && Math.abs(t.clientY - lastY) < 20) {
          lastTap = 0;
          var w = wordAt(t.clientX, t.clientY);
          if (w) {
            try { ev.preventDefault(); } catch (e) {}
            try { if (window.getSelection) { window.getSelection().removeAllRanges(); } } catch (e) {}
            post('dkWordTap', w);
          }
          return;
        }
        lastTap = now; lastX = t.clientX; lastY = t.clientY;
      }, { passive: false, capture: true });
    })();
    """#

    /// Mark every occurrence of the saved words (accent wash) and the looked-up words (red dashed
    /// underline) on the page. `rgb` is "r, g, b" for the accent. Re-runnable: highlights are
    /// replaced, marks are unwrapped first.
    static func decorate(saved: Set<String>, lookedUp: Set<String>, rgb: String) -> String {
        let savedJSON = json(Array(saved))
        let lookJSON = json(Array(lookedUp))
        return """
        (function (saved, looked) {
          var style = document.getElementById('dk-reader-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'dk-reader-style';
            style.textContent =
              '::highlight(dk-saved) { background-color: rgba(\(rgb), 0.24); }' +
              '::highlight(dk-lookup) { text-decoration: underline dashed rgba(255, 59, 48, 0.9); text-underline-offset: 2px; }' +
              'mark.dk-saved { background: rgba(\(rgb), 0.24); color: inherit; }' +
              'mark.dk-lookup { background: none; color: inherit; text-decoration: underline dashed rgba(255, 59, 48, 0.9); }';
            (document.head || document.documentElement).appendChild(style);
          }
          var useHL = !!(window.CSS && CSS.highlights && typeof Highlight !== 'undefined');
          if (!useHL) {
            var old = document.querySelectorAll('mark[data-dk-mark]');
            for (var o = 0; o < old.length; o++) {
              var parent = old[o].parentNode;
              if (!parent) { continue; }
              parent.replaceChild(document.createTextNode(old[o].textContent), old[o]);
              try { parent.normalize(); } catch (e) {}
            }
          }
          var savedSet = {}, lookSet = {};
          for (var i = 0; i < saved.length; i++) { savedSet[saved[i]] = 1; }
          for (var j = 0; j < looked.length; j++) { lookSet[looked[j]] = 1; }
          if (!saved.length && !looked.length) {
            if (useHL) { CSS.highlights.delete('dk-saved'); CSS.highlights.delete('dk-lookup'); }
            return '';
          }
          var WORD = /[\\p{L}\\p{M}][\\p{L}\\p{M}\\-'’]*/gu;
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function (n) {
              var p = n.parentElement;
              if (!p) { return NodeFilter.FILTER_REJECT; }
              if (/^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA|INPUT|SELECT|OPTION)$/.test(p.tagName)) { return NodeFilter.FILTER_REJECT; }
              return (n.nodeValue && n.nodeValue.trim()) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
            }
          });
          var savedRanges = [], lookRanges = [], node, count = 0;
          while ((node = walker.nextNode()) && count < 20000) {
            var text = node.nodeValue, m;
            WORD.lastIndex = 0;
            while ((m = WORD.exec(text)) !== null) {
              var w = m[0].toLowerCase();
              var bucket = savedSet[w] ? savedRanges : (lookSet[w] ? lookRanges : null);
              if (!bucket) { continue; }
              var r = document.createRange();
              r.setStart(node, m.index);
              r.setEnd(node, m.index + m[0].length);
              bucket.push(r);
              count++;
            }
          }
          if (useHL) {
            CSS.highlights.set('dk-saved', new Highlight(...savedRanges));
            CSS.highlights.set('dk-lookup', new Highlight(...lookRanges));
            return '';
          }
          // Wrap later ranges first so earlier offsets in the same text node stay valid.
          function wrap(ranges, cls) {
            for (var k = ranges.length - 1; k >= 0; k--) {
              try {
                var mark = document.createElement('mark');
                mark.className = cls;
                mark.setAttribute('data-dk-mark', '1');
                ranges[k].surroundContents(mark);
              } catch (e) {}
            }
          }
          wrap(lookRanges, 'dk-lookup');
          wrap(savedRanges, 'dk-saved');
          return '';
        })(\(savedJSON), \(lookJSON))
        """
    }

    private static func json(_ words: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: words),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

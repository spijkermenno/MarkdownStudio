// Preview page logic: rendering into the DOM, sanitising, post-processing
// (KaTeX, Mermaid, copy buttons), scroll sync and the bridge to Swift.
(function () {
  'use strict';

  const content = document.getElementById('content');
  const themeLink = document.getElementById('theme-css');
  const customStyle = document.getElementById('custom-css');

  function post(message) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge;
    if (handler) handler.postMessage(message);
  }

  // Forward console output and errors to Xcode's console.
  ['log', 'warn', 'error'].forEach(function (level) {
    const original = console[level];
    console[level] = function () {
      const message = Array.prototype.map.call(arguments, String).join(' ');
      post({ type: 'log', level: level, message: message });
      original.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    post({ type: 'log', level: 'error', message: e.message + ' (' + e.filename + ':' + e.lineno + ')' });
  });

  let options = { theme: 'github', customCSS: '', math: true, mermaid: true, frontMatter: 'table' };
  let renderer = MDStudio.createRenderer(options);
  let lastMarkdown = null;

  // ---------------------------------------------------------------------------
  // Sanitising

  // Relative URLs are resolved against the document's folder by the native
  // scheme handler; absolute file paths are served through mdstudio://file.
  function resolveURL(url) {
    if (!url || url.charAt(0) === '#') return url;
    if (/^file:\/\//i.test(url)) return 'mdstudio://file' + url.slice(7);
    if (/^[a-z][a-z0-9+.-]*:/i.test(url)) return url;
    if (url.slice(0, 2) === '//') return 'https:' + url;
    if (url.charAt(0) === '/') return 'mdstudio://file' + url;
    // The path goes in a query parameter: in the URL path the browser would
    // collapse "../" against the root before the request reaches the app.
    return 'mdstudio://doc/?p=' + encodeURIComponent(url);
  }

  DOMPurify.addHook('afterSanitizeAttributes', function (node) {
    ['src', 'href', 'poster'].forEach(function (attr) {
      if (node.hasAttribute && node.hasAttribute(attr)) node.setAttribute(attr, resolveURL(node.getAttribute(attr)));
    });
  });

  function sanitize(html) {
    return DOMPurify.sanitize(html, {
      ADD_ATTR: ['data-line', 'data-line-end', 'data-task-line', 'data-lang'],
      FORBID_TAGS: ['iframe', 'frame', 'object', 'embed', 'form', 'base', 'meta', 'link'],
    });
  }

  // ---------------------------------------------------------------------------
  // Post-processing

  function renderMath() {
    if (!window.katex) return;
    content.querySelectorAll('.math').forEach(function (el) {
      const tex = el.textContent;
      try {
        katex.render(tex, el, {
          displayMode: !el.classList.contains('math-inline'),
          throwOnError: false,
          output: 'htmlAndMathml',
        });
      } catch (e) {
        el.classList.add('math-error');
        el.textContent = tex;
      }
    });
  }

  let mermaidLoading = null;
  const mermaidCache = new Map();
  let mermaidCounter = 0;

  function prefersDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function loadMermaid() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (!mermaidLoading) {
      mermaidLoading = new Promise(function (resolve, reject) {
        const script = document.createElement('script');
        script.src = 'mdstudio://app/vendor/mermaid.min.js';
        script.onload = function () { initMermaid(); resolve(window.mermaid); };
        script.onerror = function () { mermaidLoading = null; reject(new Error('Could not load Mermaid')); };
        document.head.appendChild(script);
      });
    }
    return mermaidLoading;
  }

  function initMermaid() {
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: prefersDark() ? 'dark' : 'default',
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    });
  }

  // Diagrams are cached by source so typing elsewhere doesn't re-render them.
  function renderMermaid() {
    const blocks = Array.prototype.slice.call(content.querySelectorAll('pre.mermaid'));
    if (!blocks.length) return Promise.resolve();
    return loadMermaid().then(function (mermaid) {
      return Promise.all(blocks.map(function (pre) {
        const source = pre.textContent;
        const container = pre.parentElement;
        if (mermaidCache.has(source)) {
          container.innerHTML = mermaidCache.get(source);
          return Promise.resolve();
        }
        const id = 'mermaid-' + (++mermaidCounter);
        return mermaid.render(id, source).then(function (result) {
          mermaidCache.set(source, result.svg);
          container.innerHTML = result.svg;
        }).catch(function (err) {
          const stray = document.getElementById('d' + id);
          if (stray) stray.remove();
          container.innerHTML = '';
          const error = document.createElement('pre');
          error.className = 'mermaid-error';
          error.textContent = 'Mermaid error: ' + (err && err.message ? err.message : String(err));
          container.appendChild(error);
        });
      }));
    }).catch(function (err) {
      console.error(String(err));
    });
  }

  function addCopyButtons() {
    content.querySelectorAll('pre.code-block').forEach(function (pre) {
      const button = document.createElement('button');
      button.className = 'copy-button';
      button.type = 'button';
      button.textContent = 'Copy';
      button.setAttribute('aria-label', 'Copy code');
      pre.appendChild(button);
    });
  }

  // ---------------------------------------------------------------------------
  // Line mapping (scroll sync)

  let lineEntries = null;

  function buildLineEntries() {
    const scrollY = window.scrollY;
    lineEntries = Array.prototype.slice.call(content.querySelectorAll('[data-line]'))
      .filter(function (el) { return !el.closest('.footnotes'); })
      .map(function (el) {
        const rect = el.getBoundingClientRect();
        const line = Number(el.getAttribute('data-line'));
        const end = Number(el.getAttribute('data-line-end') || line + 1);
        return { line: line, end: Math.max(end, line + 1), top: rect.top + scrollY, bottom: rect.bottom + scrollY };
      })
      .filter(function (entry) { return entry.bottom > entry.top || entry.line === 0; });
    return lineEntries;
  }

  function entries() {
    return lineEntries || buildLineEntries();
  }

  function topPadding() {
    const list = entries();
    return list.length ? list[0].top : 0;
  }

  function offsetForLine(line) {
    const list = entries();
    if (!list.length) return 0;
    let inside = null;
    let before = null;
    let after = null;
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      if (e.line <= line && line < e.end) inside = e;
      if (e.end <= line) before = e;
      if (e.line > line && !after) after = e;
    }
    if (inside) return inside.top + (line - inside.line) / (inside.end - inside.line) * (inside.bottom - inside.top);
    if (before && after) {
      const span = after.line - before.end;
      const fraction = span > 0 ? (line - before.end) / span : 0;
      return before.bottom + fraction * (after.top - before.bottom);
    }
    if (after) return after.top;
    return before ? before.bottom : 0;
  }

  function lineForOffset(y) {
    const list = entries();
    if (!list.length) return 0;
    let inside = null;
    let before = null;
    let after = null;
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      if (e.top <= y && y < e.bottom) inside = e;
      if (e.bottom <= y) before = e;
      if (e.top > y && !after) after = e;
    }
    if (inside) return inside.line + (y - inside.top) / (inside.bottom - inside.top) * (inside.end - inside.line);
    if (before && after) {
      const gap = after.top - before.bottom;
      const fraction = gap > 0 ? (y - before.bottom) / gap : 0;
      return before.end + fraction * (after.line - before.end);
    }
    if (after) return after.line * (y / Math.max(after.top, 1));
    return before ? before.end : 0;
  }

  let suppressScrollUntil = 0;
  let scrollFrame = 0;

  function maxScroll() {
    return Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  }

  function scrollToY(y) {
    suppressScrollUntil = performance.now() + 150;
    window.scrollTo(0, Math.max(0, Math.min(y, maxScroll())));
  }

  window.addEventListener('scroll', function () {
    if (performance.now() < suppressScrollUntil || scrollFrame) return;
    scrollFrame = requestAnimationFrame(function () {
      scrollFrame = 0;
      const atBottom = maxScroll() > 0 && window.scrollY >= maxScroll() - 2;
      post({ type: 'scroll', line: lineForOffset(window.scrollY + topPadding()), atBottom: atBottom });
    });
  }, { passive: true });

  window.addEventListener('resize', function () { lineEntries = null; });

  // ---------------------------------------------------------------------------
  // Interaction

  content.addEventListener('click', function (event) {
    const target = event.target;

    if (target.classList && target.classList.contains('task-list-item-checkbox')) {
      post({ type: 'toggleTask', line: Number(target.getAttribute('data-task-line')) });
      return;
    }

    if (target.classList && target.classList.contains('copy-button')) {
      const code = target.parentElement.querySelector('code');
      post({ type: 'copy', text: code ? code.textContent : '' });
      target.textContent = 'Copied';
      target.classList.add('copied');
      setTimeout(function () { target.textContent = 'Copy'; target.classList.remove('copied'); }, 1200);
      return;
    }

    const link = target.closest && target.closest('a[href^="#"]');
    if (link) {
      event.preventDefault();
      const id = decodeURIComponent(link.getAttribute('href').slice(1));
      const destination = document.getElementById(id) || document.getElementsByName(id)[0];
      if (destination) {
        destination.scrollIntoView({ block: 'start' });
        flash(destination);
      }
    }
  });

  content.addEventListener('dblclick', function (event) {
    const el = event.target.closest && event.target.closest('[data-line]');
    if (el) post({ type: 'reveal', line: Number(el.getAttribute('data-line')) });
  });

  function flash(el) {
    el.classList.remove('flash');
    void el.offsetWidth;
    el.classList.add('flash');
  }

  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
      if (!window.mermaid) return;
      initMermaid();
      mermaidCache.clear();
      if (lastMarkdown !== null) MDPreview.render(lastMarkdown, true);
    });
  }

  // ---------------------------------------------------------------------------
  // Public API (called from Swift)

  window.MDPreview = {
    configure: function (newOptions) {
      const rendererChanged = ['math', 'mermaid', 'frontMatter'].some(function (key) {
        return key in newOptions && newOptions[key] !== options[key];
      });
      options = Object.assign({}, options, newOptions);
      themeLink.setAttribute('href', 'mdstudio://app/themes/' + options.theme + '.css');
      customStyle.textContent = options.customCSS || '';
      if (rendererChanged) {
        renderer = MDStudio.createRenderer(options);
        if (lastMarkdown !== null) return MDPreview.render(lastMarkdown, true);
      }
      lineEntries = null;
      return Promise.resolve(true);
    },

    render: function (markdown, force) {
      if (!force && markdown === lastMarkdown) return Promise.resolve(true);
      lastMarkdown = markdown;
      const scrollY = window.scrollY;
      const result = renderer.render(markdown);
      content.innerHTML = sanitize(result.html);
      if (result.hasMath) renderMath();
      addCopyButtons();
      lineEntries = null;
      window.scrollTo(0, scrollY);
      suppressScrollUntil = performance.now() + 100;
      const pending = result.hasMermaid && options.mermaid ? renderMermaid() : Promise.resolve();
      return pending.then(function () {
        lineEntries = null;
        // Wait for images so exported PDFs and scroll positions are correct.
        const images = Array.prototype.filter.call(content.querySelectorAll('img'), function (img) { return !img.complete; });
        return Promise.all(images.map(function (img) {
          return new Promise(function (resolve) {
            img.addEventListener('load', resolve, { once: true });
            img.addEventListener('error', resolve, { once: true });
            setTimeout(resolve, 3000);
          });
        }));
      }).then(function () {
        lineEntries = null;
        return true;
      });
    },

    scrollToLine: function (line, atBottom) {
      if (atBottom) { scrollToY(maxScroll()); return; }
      scrollToY(offsetForLine(line) - topPadding());
    },

    revealLine: function (line) {
      const target = offsetForLine(line);
      scrollToY(target - topPadding());
      const el = entries().filter(function (e) { return e.line <= line; }).pop();
      if (el) {
        const node = Array.prototype.find.call(content.querySelectorAll('[data-line]'), function (n) {
          return Number(n.getAttribute('data-line')) === el.line;
        });
        if (node) flash(node);
      }
    },

    exportHTML: function () {
      const clone = content.cloneNode(true);
      clone.querySelectorAll('.copy-button').forEach(function (b) { b.remove(); });
      clone.querySelectorAll('[data-line], [data-line-end]').forEach(function (el) {
        el.removeAttribute('data-line');
        el.removeAttribute('data-line-end');
      });
      clone.querySelectorAll('input.task-list-item-checkbox').forEach(function (input) {
        input.setAttribute('disabled', '');
        input.removeAttribute('data-task-line');
        if (input.checked) input.setAttribute('checked', '');
      });
      // Turn preview-only URLs back into paths that work next to the document.
      clone.querySelectorAll('[src], [href], [poster]').forEach(function (el) {
        ['src', 'href', 'poster'].forEach(function (attr) {
          const value = el.getAttribute(attr);
          if (!value) return;
          if (value.indexOf('mdstudio://doc/?p=') === 0) el.setAttribute(attr, decodeURIComponent(value.slice('mdstudio://doc/?p='.length)));
          else if (value.indexOf('mdstudio://doc/') === 0) el.setAttribute(attr, value.slice('mdstudio://doc/'.length));
          else if (value.indexOf('mdstudio://file/') === 0) el.setAttribute(attr, 'file:///' + value.slice('mdstudio://file/'.length));
        });
      });
      return clone.innerHTML;
    },

    stylesheets: function () {
      return {
        theme: options.theme,
        customCSS: options.customCSS || '',
        hasMath: !!content.querySelector('.katex'),
      };
    },
  };

  post({ type: 'ready' });
})();

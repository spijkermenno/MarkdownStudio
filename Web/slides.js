// Presentation mode: splits the rendered document into slides.
(function () {
  'use strict';

  const deck = document.getElementById('deck');
  const notesPanel = document.getElementById('notes-panel');
  const notesText = document.getElementById('notes-text');
  const counter = document.getElementById('counter');
  const timerLabel = document.getElementById('timer');
  const progressBar = document.getElementById('progress-bar');

  let slides = [];
  let index = 0;
  let startedAt = Date.now();

  function post(message) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slides;
    if (handler) handler.postMessage(message);
  }

  // Same URL handling as the preview, on its own DOMPurify instance.
  const purifier = DOMPurify(window);
  purifier.addHook('afterSanitizeAttributes', function (node) {
    ['src', 'href'].forEach(function (attr) {
      if (!node.hasAttribute || !node.hasAttribute(attr)) return;
      const url = node.getAttribute(attr);
      if (!url || url.charAt(0) === '#' || /^[a-z][a-z0-9+.-]*:/i.test(url)) return;
      node.setAttribute(attr, url.charAt(0) === '/' ? 'mdstudio://file' + url : 'mdstudio://doc/?p=' + encodeURIComponent(url));
    });
  });

  // mode: 'rule' (---), 'heading' (# and ##) or 'auto'.
  function split(html, mode) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const nodes = Array.from(template.content.childNodes);
    if (mode === 'auto') mode = nodes.some((n) => n.nodeName === 'HR') ? 'rule' : 'heading';

    const result = [{ nodes: [], notes: [] }];
    const current = () => result[result.length - 1];
    const hasContent = (s) => s.nodes.some((n) => n.nodeType === 1 || (n.nodeType === 3 && n.textContent.trim()));
    nodes.forEach(function (node) {
      if (node.nodeType === 8) {
        const text = node.data.trim();
        if (/^notes?:/i.test(text)) current().notes.push(text.replace(/^notes?:\s*/i, ''));
        return;
      }
      if (mode === 'rule' && node.nodeName === 'HR') { result.push({ nodes: [], notes: [] }); return; }
      if (mode === 'heading' && (node.nodeName === 'H1' || node.nodeName === 'H2') && hasContent(current())) {
        result.push({ nodes: [], notes: [] });
      }
      if (node.nodeType === 1 && node.classList.contains('front-matter')) return;
      current().nodes.push(node);
    });
    return result.filter(hasContent);
  }

  function renderMath(root) {
    if (!window.katex) return;
    root.querySelectorAll('.math').forEach(function (el) {
      try {
        katex.render(el.textContent, el, { displayMode: !el.classList.contains('math-inline'), throwOnError: false });
      } catch (e) { /* leave TeX source */ }
    });
  }

  function loadMermaid() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    return new Promise(function (resolve, reject) {
      const script = document.createElement('script');
      script.src = 'mdstudio://app/vendor/mermaid.min.js';
      script.onload = function () {
        const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
        resolve(window.mermaid);
      };
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  function renderMermaid() {
    const blocks = Array.from(deck.querySelectorAll('pre.mermaid'));
    if (!blocks.length) return Promise.resolve();
    return loadMermaid().then(function (mermaid) {
      return Promise.all(blocks.map(function (pre, i) {
        return mermaid.render('slide-mermaid-' + i, pre.textContent)
          .then(function (r) { pre.parentElement.innerHTML = r.svg; })
          .catch(function () { /* leave source visible */ });
      }));
    }).catch(function () {});
  }

  // Shrinks the font until the slide's content fits.
  function fit(slide) {
    const body = slide.firstElementChild;
    let size = 34;
    body.style.setProperty('--slide-font', size + 'px');
    const wasActive = slide.classList.contains('active');
    slide.classList.add('active');
    while (size > 14 && (body.scrollHeight > 720 || body.scrollWidth > 1280)) {
      size -= 2;
      body.style.setProperty('--slide-font', size + 'px');
    }
    if (!wasActive) slide.classList.remove('active');
  }

  function layout() {
    const scale = Math.min(window.innerWidth / 1280, window.innerHeight / 720);
    slides.forEach(function (s) { s.el.style.transform = 'translate(-50%, -50%) scale(' + scale + ')'; });
  }

  function titleOf(slide) {
    const heading = slide && slide.el.querySelector('h1, h2, h3');
    return heading ? heading.textContent.trim() : '';
  }

  function show(i) {
    if (!slides.length) return;
    index = Math.max(0, Math.min(i, slides.length - 1));
    slides.forEach(function (s, n) { s.el.classList.toggle('active', n === index); });
    notesText.textContent = slides[index].notes.join('\n\n');
    counter.textContent = (index + 1) + ' / ' + slides.length;
    progressBar.style.width = ((index + 1) / slides.length * 100) + '%';
    post({ type: 'slide', index: index, count: slides.length, notes: slides[index].notes.join('\n\n'),
           title: titleOf(slides[index]), nextTitle: titleOf(slides[index + 1]) });
  }

  setInterval(function () {
    const seconds = Math.floor((Date.now() - startedAt) / 1000);
    timerLabel.textContent = String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }, 1000);

  document.addEventListener('keydown', function (e) {
    switch (e.key) {
      case 'ArrowRight': case 'ArrowDown': case 'PageDown': case ' ': case 'Enter': show(index + 1); break;
      case 'ArrowLeft': case 'ArrowUp': case 'PageUp': case 'Backspace': show(index - 1); break;
      case 'Home': show(0); break;
      case 'End': show(slides.length - 1); break;
      case 'n': case 'N': notesPanel.hidden = !notesPanel.hidden; break;
      case 'Escape': post({ type: 'exit' }); break;
      default: return;
    }
    e.preventDefault();
  });
  document.addEventListener('click', function (e) {
    if (e.target.closest('a')) return;
    show(index + (e.clientX < window.innerWidth / 4 ? -1 : 1));
  });
  window.addEventListener('resize', layout);

  function setStylesheet(link, href) {
    if (link.getAttribute('href') === href && link.sheet) return Promise.resolve();
    return new Promise(function (resolve) {
      link.addEventListener('load', resolve, { once: true });
      link.addEventListener('error', resolve, { once: true });
      setTimeout(resolve, 2000);
      link.setAttribute('href', href);
    });
  }

  function waitForImages() {
    const pending = Array.prototype.filter.call(deck.querySelectorAll('img'), function (img) { return !img.complete; });
    return Promise.all(pending.map(function (img) {
      return new Promise(function (resolve) {
        img.addEventListener('load', resolve, { once: true });
        img.addEventListener('error', resolve, { once: true });
        setTimeout(resolve, 3000);
      });
    }));
  }

  window.MDSlides = {
    // options: { theme, customCSS, math, mermaid, separator, startAt }
    load: function (markdown, options) {
      options = options || {};
      const themeReady = setStylesheet(document.getElementById('theme-css'),
                                       'mdstudio://app/themes/' + (options.theme || 'github') + '.css');
      document.getElementById('custom-css').textContent = options.customCSS || '';
      const renderer = MDStudio.createRenderer({ math: options.math !== false, mermaid: options.mermaid !== false, frontMatter: 'hide' });
      const parts = split(renderer.render(markdown).html, options.separator || 'auto');
      deck.innerHTML = '';
      slides = parts.map(function (part, i) {
        const wrapper = document.createElement('div');
        part.nodes.forEach(function (n) { wrapper.appendChild(n); });
        const el = document.createElement('section');
        el.className = 'slide';
        const body = document.createElement('div');
        body.className = 'markdown-body';
        body.innerHTML = purifier.sanitize(wrapper.innerHTML);
        el.appendChild(body);
        // A first slide with only a heading (and maybe a line or two) is a title slide.
        if (i === 0 && body.children.length <= 3 && body.querySelector('h1')) el.classList.add('title-slide');
        deck.appendChild(el);
        return { el: el, notes: part.notes };
      });
      renderMath(deck);
      // Measure only once the theme CSS, diagrams and images are in, so the
      // font fitting is right and exported PDFs include the images.
      return Promise.all([themeReady, renderMermaid()]).then(waitForImages).then(function () {
        slides.forEach(function (s) { fit(s.el); });
        layout();
        startedAt = Date.now();
        show(options.startAt || 0);
        return slides.length;
      });
    },
    go: function (i) { show(i); return index; },
    next: function () { show(index + 1); return index; },
    previous: function () { show(index - 1); return index; },
    showNotes: function (visible) { notesPanel.hidden = !visible; },
  };

  post({ type: 'ready' });
})();

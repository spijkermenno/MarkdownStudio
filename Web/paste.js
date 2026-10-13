// Converts HTML from the clipboard (web pages, Google Docs, Word, Notion) to
// Markdown with Turndown. Runs in the preview's web view because Turndown
// needs a real HTML parser.
(function () {
  'use strict';

  // A separate DOMPurify instance: the preview's instance rewrites URLs.
  const purifier = DOMPurify(window);
  let service = null;

  function makeService() {
    const s = new TurndownService({
      headingStyle: 'atx', hr: '---', bulletListMarker: '-', codeBlockStyle: 'fenced',
      fence: '```', emDelimiter: '*', strongDelimiter: '**', linkStyle: 'inlined',
    });
    s.use(turndownPluginGfm.gfm);
    // markdown-it uses ~~ for strikethrough (a single ~ is subscript).
    s.addRule('strikethrough', { filter: ['del', 's', 'strike'], replacement: (c) => (c.trim() ? '~~' + c + '~~' : c) });
    s.addRule('mark', { filter: ['mark'], replacement: (c) => '==' + c + '==' });
    s.addRule('sub', { filter: ['sub'], replacement: (c) => '~' + c + '~' });
    s.addRule('sup', { filter: ['sup'], replacement: (c) => '^' + c + '^' });
    // Images that only exist where they were copied from can't be linked.
    s.addRule('localImages', {
      filter: (node) => node.nodeName === 'IMG' && /^(file|data|blob|cid):/i.test(node.getAttribute('src') || ''),
      replacement: (c, node) => node.getAttribute('alt') || '',
    });
    s.remove(['style', 'script', 'meta', 'title', 'link', 'noscript']);
    return s;
  }

  // Google Docs and Word express formatting with inline styles; turn the
  // common ones into tags before styles are stripped.
  function normalize(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const root = template.content;
    root.querySelectorAll('b[id^="docs-internal-guid"]').forEach((b) => b.replaceWith(...b.childNodes));
    root.querySelectorAll('span[style]').forEach((span) => {
      const style = span.getAttribute('style').toLowerCase();
      let node = span;
      const wrap = (tag) => { const el = document.createElement(tag); el.append(...node.childNodes); node.append(el); node = el; };
      if (/font-weight:\s*(bold|[6-9]00)/.test(style)) wrap('strong');
      if (/font-style:\s*italic/.test(style)) wrap('em');
      if (/text-decoration[^;]*line-through/.test(style)) wrap('del');
    });
    // Word's empty spacer paragraphs.
    root.querySelectorAll('o\\:p').forEach((el) => el.remove());
    const container = document.createElement('div');
    container.appendChild(root);
    return container.innerHTML;
  }

  window.MDPaste = {
    convert: function (html) {
      service = service || makeService();
      const clean = purifier.sanitize(normalize(html), { FORBID_ATTR: ['style', 'class'] });
      return service.turndown(clean)
        .replace(/ /g, ' ')
        // Strip trailing whitespace, but keep the two spaces that mark a <br> hard break.
        .replace(/[ \t]+\n/g, (m) => (/^ {2,}\n$/.test(m) ? '  \n' : '\n'))
        .replace(/\n{3,}/g, '\n\n')
        .trim();
    },
  };
})();

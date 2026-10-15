// Markdown → HTML rendering for Markdown Studio.
//
// This file has no DOM dependencies so it can run inside the preview's
// WKWebView, in JavaScriptCore (unit tests) and in Node (development).
// It expects the markdown-it UMD bundles to be loaded first; they register
// themselves as globals (markdownit, markdownitFootnote, …).
(function (root) {
  'use strict';

  // ---------------------------------------------------------------------------
  // Helpers

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // GitHub-style heading slugs: lowercase, strip punctuation, spaces → dashes.
  function slugify(text) {
    return String(text)
      .trim()
      .toLowerCase()
      .replace(/<[^>]*>/g, '')
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s+/g, '-');
  }

  function isWhitespace(code) {
    return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
  }

  function lineAttrs(token) {
    const line = token.attrGet && token.attrGet('data-line');
    if (line === null || line === undefined) return '';
    const end = token.attrGet('data-line-end');
    return ' data-line="' + line + '"' + (end !== null ? ' data-line-end="' + end + '"' : '');
  }

  // ---------------------------------------------------------------------------
  // YAML front matter

  // Detects a leading `---` … `---` (or `...`) block. Only treated as front
  // matter when it contains at least one `key: value` line, so a document that
  // simply starts with a horizontal rule keeps rendering as one.
  function parseFrontMatter(src) {
    const match = /^---[ \t]*\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/.exec(src);
    if (!match) return null;
    const raw = match[1];
    if (!/^[\w"'][^:\n]*:/m.test(raw)) return null;

    const entries = [];
    raw.split(/\r?\n/).forEach(function (line) {
      const kv = /^([\w"'][^:]*):\s*(.*)$/.exec(line);
      if (kv && !/^\s/.test(line)) {
        entries.push([kv[1].replace(/^["']|["']$/g, ''), kv[2]]);
      } else if (entries.length && line.trim()) {
        const last = entries[entries.length - 1];
        last[1] = (last[1] ? last[1] + '\n' : '') + line.trim();
      }
    });

    const consumed = match[0];
    return {
      raw: raw,
      entries: entries,
      lineCount: consumed.split(/\n/).length - (consumed.endsWith('\n') ? 1 : 0),
      body: src.slice(consumed.length),
    };
  }

  // ---------------------------------------------------------------------------
  // Accessibility helpers

  // A BCP 47-like language tag ("nl", "en-GB", "zh-Hant-TW"), or null.
  function normalizeLang(value) {
    const tag = String(value || '').trim().replace(/^["']|["']$/g, '').replace(/_/g, '-');
    return /^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$/.test(tag) ? tag : null;
  }

  // The document language from a `lang:` (or `language:`) front matter key.
  function frontMatterLang(fm) {
    if (!fm) return null;
    const entry = fm.entries.find(function (e) { return /^(lang|language)$/i.test(e[0]); });
    return entry ? normalizeLang(entry[1]) : null;
  }

  // Accessible name for a Mermaid diagram: its accTitle and accDescr when the
  // author wrote them, otherwise "Diagram".
  function diagramLabel(source) {
    const src = String(source || '');
    const title = /^\s*accTitle\s*:\s*(.+)$/m.exec(src);
    const descr = /^\s*accDescr\s*:\s*(.+)$/m.exec(src) || /^\s*accDescr\s*\{([\s\S]*?)\}/m.exec(src);
    const parts = [title && title[1].trim(), descr && descr[1].replace(/\s+/g, ' ').trim()].filter(Boolean);
    return parts.length ? parts.join('. ') : 'Diagram';
  }

  // ---------------------------------------------------------------------------
  // Plugins

  // Adds data-line / data-line-end attributes to block tokens so the preview
  // can be mapped back to source lines (scroll sync, ⌘-click to reveal).
  function sourceLinePlugin(md) {
    md.core.ruler.push('source_lines', function (state) {
      const offset = state.env.lineOffset || 0;
      state.tokens.forEach(function (token) {
        if (!token.map || !token.block) return;
        if (token.nesting === 1 || token.type === 'fence' || token.type === 'code_block' ||
            token.type === 'hr' || token.type === 'math_block') {
          token.attrSet('data-line', String(token.map[0] + offset));
          token.attrSet('data-line-end', String(token.map[1] + offset));
        }
      });
    });
  }

  // Heading IDs: `### My Heading {#custom-id}` uses the custom id, every
  // other heading gets a unique GitHub-style slug.
  function headingIdPlugin(md) {
    md.core.ruler.after('inline', 'heading_ids', function (state) {
      const used = Object.create(null);
      const tokens = state.tokens;
      for (let i = 0; i < tokens.length; i++) {
        if (tokens[i].type !== 'heading_open') continue;
        const inline = tokens[i + 1];
        if (!inline || inline.type !== 'inline') continue;

        let id = null;
        const custom = /\s*\{#([\w\-:.]+)\}\s*$/.exec(inline.content);
        const children = inline.children || [];
        const last = children[children.length - 1];
        if (custom && last && last.type === 'text' && /\{#[\w\-:.]+\}\s*$/.test(last.content)) {
          id = custom[1];
          last.content = last.content.replace(/\s*\{#[\w\-:.]+\}\s*$/, '');
          inline.content = inline.content.slice(0, custom.index);
        } else {
          const text = children
            .filter(function (t) { return t.type === 'text' || t.type === 'code_inline' || t.type === 'emoji'; })
            .map(function (t) { return t.type === 'emoji' ? '' : t.content; })
            .join('');
          id = slugify(text) || 'section';
        }

        let unique = id;
        let n = 1;
        while (used[unique]) unique = id + '-' + n++;
        used[unique] = true;
        tokens[i].attrSet('id', unique);
      }
    });
  }

  // Task lists: `- [ ] todo` / `- [x] done`. Checkboxes carry the source line
  // so a click in the preview can toggle the box in the source text.
  function taskListPlugin(md) {
    md.core.ruler.after('inline', 'task_lists', function (state) {
      const tokens = state.tokens;
      const offset = state.env.lineOffset || 0;
      for (let i = 2; i < tokens.length; i++) {
        const inline = tokens[i];
        if (inline.type !== 'inline' || tokens[i - 1].type !== 'paragraph_open' ||
            tokens[i - 2].type !== 'list_item_open') continue;
        const match = /^\[([ xX])\](?=\s|$)/.exec(inline.content);
        if (!match) continue;
        const first = inline.children[0];
        if (!first || first.type !== 'text' || !/^\[[ xX]\]/.test(first.content)) continue;

        first.content = first.content.slice(3).replace(/^\s/, '');
        const checked = match[1] !== ' ';
        const item = tokens[i - 2];
        const line = (item.map ? item.map[0] : 0) + offset;
        // The label gives the checkbox the task text as its accessible name,
        // and lets a click on the text toggle the box.
        const checkbox = new state.Token('html_inline', '', 0);
        checkbox.content = '<label class="task-list-item-label"><input type="checkbox" class="task-list-item-checkbox" data-task-line="' +
          line + '"' + (checked ? ' checked' : '') + '> ';
        const close = new state.Token('html_inline', '', 0);
        close.content = '</label>';
        inline.children.unshift(checkbox);
        inline.children.push(close);

        item.attrJoin('class', 'task-list-item');
        for (let j = i - 3; j >= 0; j--) {
          const t = tokens[j];
          if ((t.type === 'bullet_list_open' || t.type === 'ordered_list_open') && t.level === item.level - 1) {
            if (!(t.attrGet('class') || '').includes('contains-task-list')) t.attrJoin('class', 'contains-task-list');
            break;
          }
        }
      }
    });
  }

  // Math: `$inline$`, `$$display$$` and `$$` blocks. The TeX source is emitted
  // as escaped text and typeset by KaTeX in the preview.
  function mathPlugin(md) {
    function findClosing(src, from, delim) {
      let pos = from;
      while ((pos = src.indexOf(delim, pos)) !== -1) {
        let backslashes = 0;
        for (let p = pos - 1; src.charCodeAt(p) === 0x5c; p--) backslashes++;
        if (backslashes % 2 === 1) { pos += 1; continue; }
        if (delim === '$') {
          const prev = src.charCodeAt(pos - 1);
          const next = src.charCodeAt(pos + 1);
          if (isWhitespace(prev) || (next >= 0x30 && next <= 0x39)) { pos += 1; continue; }
        }
        return pos;
      }
      return -1;
    }

    function mathInline(state, silent) {
      const src = state.src;
      const start = state.pos;
      if (src.charCodeAt(start) !== 0x24 /* $ */) return false;

      const display = src.charCodeAt(start + 1) === 0x24;
      const delim = display ? '$$' : '$';
      const contentStart = start + delim.length;
      const first = src.charCodeAt(contentStart);
      if (isNaN(first) || (!display && isWhitespace(first))) return false;

      const end = findClosing(src, contentStart, delim);
      if (end === -1 || end === contentStart || end > state.posMax) return false;

      if (!silent) {
        const token = state.push(display ? 'math_display' : 'math_inline', 'math', 0);
        token.markup = delim;
        token.content = src.slice(contentStart, end);
      }
      state.pos = end + delim.length;
      return true;
    }

    function mathBlock(state, startLine, endLine, silent) {
      let pos = state.bMarks[startLine] + state.tShift[startLine];
      let max = state.eMarks[startLine];
      if (state.sCount[startLine] - state.blkIndent >= 4) return false;
      if (pos + 2 > max || state.src.slice(pos, pos + 2) !== '$$') return false;

      const firstLine = state.src.slice(pos + 2, max).trim();
      let content;
      let nextLine = startLine;
      let found = false;

      if (firstLine.length >= 2 && firstLine.endsWith('$$')) {
        content = firstLine.slice(0, -2);
        found = true;
      } else {
        const lines = firstLine ? [firstLine] : [];
        while (++nextLine < endLine) {
          pos = state.bMarks[nextLine] + state.tShift[nextLine];
          max = state.eMarks[nextLine];
          if (pos < max && state.sCount[nextLine] < state.blkIndent) break;
          const line = state.src.slice(pos, max).trim();
          if (line.endsWith('$$')) {
            const rest = line.slice(0, -2);
            if (rest) lines.push(rest);
            found = true;
            break;
          }
          lines.push(line);
        }
        content = lines.join('\n');
      }
      if (!found) return false;
      if (silent) return true;

      state.line = nextLine + 1;
      const token = state.push('math_block', 'math', 0);
      token.block = true;
      token.content = content;
      token.markup = '$$';
      token.map = [startLine, state.line];
      return true;
    }

    md.inline.ruler.after('escape', 'math_inline', mathInline);
    md.block.ruler.before('fence', 'math_block', mathBlock, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });

    md.renderer.rules.math_inline = function (tokens, idx) {
      return '<span class="math math-inline">' + escapeHtml(tokens[idx].content) + '</span>';
    };
    md.renderer.rules.math_display = function (tokens, idx) {
      return '<span class="math math-display">' + escapeHtml(tokens[idx].content) + '</span>';
    };
    md.renderer.rules.math_block = function (tokens, idx) {
      return '<div class="math math-block"' + lineAttrs(tokens[idx]) + '>' + escapeHtml(tokens[idx].content) + '</div>\n';
    };
  }

  // ---------------------------------------------------------------------------
  // Renderer

  // options: { math, mermaid, frontMatter: 'hide' | 'table' | 'code', hljs }
  function createRenderer(options) {
    const opts = Object.assign({ math: true, mermaid: true, frontMatter: 'table', hljs: root.hljs }, options || {});
    const hljs = opts.hljs;

    function highlight(code, lang) {
      if (hljs && lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value; } catch (e) { /* fall through */ }
      }
      return escapeHtml(code);
    }

    const md = root.markdownit({ html: true, linkify: true, typographer: false, breaks: false })
      .use(root.markdownitFootnote)
      .use(root.markdownitDeflist)
      .use(root.markdownitMark)
      .use(root.markdownitSub)
      .use(root.markdownitSup)
      .use(root.markdownitEmoji, { shortcuts: {} })
      .use(headingIdPlugin)
      .use(taskListPlugin);
    if (opts.math) md.use(mathPlugin);
    md.use(sourceLinePlugin);

    md.renderer.rules.fence = function (tokens, idx) {
      const token = tokens[idx];
      const info = token.info ? md.utils.unescapeAll(token.info).trim() : '';
      const lang = info.split(/\s+/)[0];
      const attrs = lineAttrs(token);

      if (lang === 'mermaid' && opts.mermaid) {
        return '<div class="mermaid-block"' + attrs + '><pre class="mermaid">' + escapeHtml(token.content) + '</pre></div>\n';
      }
      if ((lang === 'math' || lang === 'latex' || lang === 'katex') && opts.math) {
        return '<div class="math math-block"' + attrs + '>' + escapeHtml(token.content) + '</div>\n';
      }
      const known = hljs && lang && hljs.getLanguage(lang);
      const cls = lang ? ' class="' + (known ? 'hljs ' : '') + 'language-' + escapeHtml(lang) + '"' : '';
      const langLabel = lang ? ' data-lang="' + escapeHtml(lang) + '"' : '';
      return '<pre class="code-block"' + attrs + langLabel + '><code' + cls + '>' + highlight(token.content, lang) + '</code></pre>\n';
    };

    function renderFrontMatter(fm) {
      if (!fm || opts.frontMatter === 'hide') return '';
      if (opts.frontMatter === 'code') {
        return '<pre class="code-block front-matter" data-line="0" data-line-end="' + fm.lineCount +
          '"><code class="hljs language-yaml">' + highlight(fm.raw, 'yaml') + '</code></pre>\n';
      }
      const rows = fm.entries.map(function (e) {
        return '<tr><th>' + escapeHtml(e[0]) + '</th><td>' + escapeHtml(e[1]).replace(/\n/g, '<br>') + '</td></tr>';
      }).join('');
      return '<table class="front-matter" data-line="0" data-line-end="' + fm.lineCount + '"><tbody>' + rows + '</tbody></table>\n';
    }

    return {
      markdownIt: md,
      render: function (src) {
        src = String(src || '');
        const fm = parseFrontMatter(src);
        const env = { lineOffset: fm ? fm.lineCount : 0 };
        const html = renderFrontMatter(fm) + md.render(fm ? fm.body : src, env);
        return { html: html, hasMath: opts.math && /class="math /.test(html), hasMermaid: /class="mermaid"/.test(html),
                 lang: frontMatterLang(fm) };
      },
    };
  }

  root.MDStudio = {
    createRenderer: createRenderer,
    parseFrontMatter: parseFrontMatter,
    slugify: slugify,
    escapeHtml: escapeHtml,
    normalizeLang: normalizeLang,
    diagramLabel: diagramLabel,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);

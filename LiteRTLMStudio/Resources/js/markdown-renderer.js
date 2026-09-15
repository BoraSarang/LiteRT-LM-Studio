// marked v14+ — 점진적 마크다운 렌더러

// T-111 2단계 페인트: true 구간은 하이라이트 생략(escape만) 후 별도 적용.
// 전체 렌더(방 전환·확정) 첫 페인트를 막는 동기 highlightAuto 비용 분리용.
var deferHighlight = false;

const highlightExtension = {
  renderer: {
    code({ text, lang }) {
      const code = (text || '').replace(/\n$/, '');
      const langStr = lang || '';
      let highlighted;
      if (deferHighlight) {
        highlighted = escapeHtml(code);
      } else if (langStr && hljs.getLanguage(langStr)) {
        try {
          highlighted = hljs.highlight(code, { language: langStr }).value;
        } catch (e) {
          highlighted = escapeHtml(code);
        }
      } else {
        highlighted = hljs.highlightAuto(code).value;
      }
      return '<div class="code-block"><div class="code-header"><span class="code-lang">' + escapeHtml(langStr || 'code') + '</span><button class="copy-btn" onclick="copyCode(this)">복사</button></div><pre><code class="hljs' + (langStr ? ' language-' + langStr : '') + '">' + highlighted + '</code></pre></div>\n';
    }
  }
};

marked.use(highlightExtension);

// 한글 볼드 확장 (T-066): CommonMark flanking 규칙 때문에 `**"..."**이며`
// (닫는 ** 뒤 한글 조사)나 `** ㅌㅌㅌ **`(안쪽 공백)이 볼드로 안 풀림.
// `**`로 감싸면 뒤 문자와 무관하게 볼드로 인정, 안쪽 양끝 공백은 trim.
// 코드스팬·펜스·`***`는 손대지 않음 (빈 내용은 거짓 양성 방지).
const koreanStrongExtension = {
  extensions: [{
    name: 'koreanStrong',
    level: 'inline',
    start(src) {
      const i = src.indexOf('**');
      return i === -1 ? undefined : i;
    },
    tokenizer(src) {
      const mt = /^\*\*([^*]+?)\*\*(?!\*)/.exec(src);
      if (!mt) return undefined;
      const inner = mt[1].trim();
      if (!inner) return undefined;
      return { type: 'koreanStrong', raw: mt[0], text: inner, tokens: this.lexer.inlineTokens(inner) };
    },
    renderer(token) {
      return '<strong>' + this.parser.parseInline(token.tokens) + '</strong>';
    }
  }]
};

marked.use(koreanStrongExtension);

// 토스트 메시지 표시
function showToast(msg) {
  var existing = document.getElementById('toast-msg');
  if (existing) existing.remove();
  var div = document.createElement('div');
  div.id = 'toast-msg';
  div.textContent = msg;
  div.style.cssText = 'position:fixed;bottom:16px;left:50%;transform:translateX(-50%);padding:6px 16px;border-radius:8px;font-size:12px;z-index:9999;font-family:-apple-system,sans-serif;opacity:0;transition:opacity 0.2s;';
  var isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
    (document.documentElement.getAttribute('data-theme') === 'system' && window.matchMedia('(prefers-color-scheme:dark)').matches);
  div.style.background = isDark ? 'rgba(255,255,255,0.88)' : 'rgba(0,0,0,0.78)';
  div.style.color = isDark ? '#111' : '#fff';
  document.body.appendChild(div);
  requestAnimationFrame(function() { div.style.opacity = '1'; });
  setTimeout(function() {
    div.style.opacity = '0';
    setTimeout(function() { div.remove(); }, 300);
  }, 1500);
}

function copyCode(btn) {
  var pre = btn.closest('.code-block').querySelector('pre');
  var text = pre.textContent;
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.left = '-9999px';
  document.body.appendChild(ta);
  ta.select();
  try {
    document.execCommand('copy');
    btn.textContent = '복사됨';
    showToast('클립보드로 복사되었습니다');
    setTimeout(function() { btn.textContent = '복사'; }, 1500);
  } catch(e) {
    btn.textContent = '실패';
    setTimeout(function() { btn.textContent = '복사'; }, 1500);
  }
  document.body.removeChild(ta);
}

function copyTable(btn) {
  var wrapper = btn.closest('.table-wrapper');
  var table = wrapper.querySelector('table');
  var rows = [];
  var headerDone = false;
  table.querySelectorAll('tr').forEach(function(tr) {
    var cells = [];
    tr.querySelectorAll('th, td').forEach(function(cell) {
      var text = cell.textContent.trim()
        .replace(/[\u00A0\u202F\u2009\u200A\u200B\u200C\u200D\uFEFF]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
      cells.push(text);
    });
    rows.push('| ' + cells.join(' | ') + ' |');
    if (!headerDone) {
      rows.push('| ' + cells.map(function() { return '---'; }).join(' | ') + ' |');
      headerDone = true;
    }
  });
  var text = rows.join('\n');
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.left = '-9999px';
  document.body.appendChild(ta);
  ta.select();
  try {
    document.execCommand('copy');
    btn.textContent = '복사됨';
    showToast('마크다운 테이블을 복사했습니다');
    setTimeout(function() { btn.textContent = '복사'; }, 1500);
  } catch(e) {
    btn.textContent = '실패';
    setTimeout(function() { btn.textContent = '복사'; }, 1500);
  }
  document.body.removeChild(ta);
}

// raw HTML로 통과된 bare <pre><code> 보강 — 래퍼·하이라이트·복사버튼 부여 (v1.9 T-90)
// marked의 renderer.code는 마크다운 펜스에만 호출되므로 HTML 테이블 등 raw 경로의 pre는 맨몸으로 들어온다.
function enhanceBareCodeBlocks(tmp) {
  tmp.querySelectorAll('pre > code').forEach(function(codeEl) {
    if (codeEl.closest('.code-block')) return;
    var lang = '';
    (codeEl.className || '').split(/\s+/).forEach(function(cls) {
      if (cls.indexOf('language-') === 0) lang = cls.substring(9);
    });
    var source = codeEl.textContent.replace(/\n$/, '');
    var html;
    if (deferHighlight) {
      html = escapeHtml(source);
    } else try {
      html = (lang && hljs.getLanguage(lang))
        ? hljs.highlight(source, { language: lang }).value
        : hljs.highlightAuto(source).value;
    } catch (e) {
      html = escapeHtml(source);
    }
    codeEl.innerHTML = html;
    codeEl.classList.add('hljs');
    if (lang && !codeEl.classList.contains('language-' + lang)) {
      codeEl.classList.add('language-' + lang);
    }

    var block = document.createElement('div');
    block.className = 'code-block';
    var header = document.createElement('div');
    header.className = 'code-header';
    var label = document.createElement('span');
    label.className = 'code-lang';
    label.textContent = lang || 'code';
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = '복사';
    btn.setAttribute('onclick', 'copyCode(this)');
    header.appendChild(label);
    header.appendChild(btn);
    var preEl = codeEl.parentElement; // <pre>
    if (!preEl) return;
    preEl.parentNode.insertBefore(block, preEl);
    block.appendChild(header);
    block.appendChild(preEl);
  });
}

function decorateDOM(tmp) {
  enhanceBareCodeBlocks(tmp);
  tmp.querySelectorAll('table').forEach(function(t) {
    if (t.parentElement.classList.contains('table-wrapper')) return;
    var wrapper = document.createElement('div');
    wrapper.className = 'table-wrapper';
    var header = document.createElement('div');
    header.className = 'table-header';
    var copyBtn = document.createElement('button');
    copyBtn.className = 'copy-btn';
    copyBtn.textContent = '복사';
    copyBtn.setAttribute('onclick', 'copyTable(this)');
    header.appendChild(copyBtn);
    t.parentNode.insertBefore(wrapper, t);
    wrapper.appendChild(header);
    wrapper.appendChild(t);
  });
  return tmp.innerHTML;
}

function renderMarkdown(markdown) {
  var tmp = document.createElement('div');
  tmp.innerHTML = marked.parse(markdown);
  return decorateDOM(tmp);
}

// T-111 2단계 전체 렌더: 1단계 즉시 표시+높이, 2단계 양보 후 하이라이트+높이 재보고.
// 스트리밍 append 경로는 손대지 않음 (전체 렌더=방 전환·확정만).
var paintGen = 0;
function highlightNow(root) {
  var scope = root || document.getElementById('content');
  if (!scope) return false;
  var did = false;
  scope.querySelectorAll('pre > code').forEach(function(codeEl) {
    if (codeEl.dataset.highlighted) return;
    var lang = '';
    (codeEl.className || '').split(/\s+/).forEach(function(cls) {
      if (cls.indexOf('language-') === 0) lang = cls.substring(9);
    });
    var source = codeEl.textContent.replace(/\n$/, '');
    var html;
    try {
      html = (lang && hljs.getLanguage(lang))
        ? hljs.highlight(source, { language: lang }).value
        : hljs.highlightAuto(source).value;
    } catch (e) {
      html = escapeHtml(source);
    }
    codeEl.innerHTML = html;
    codeEl.classList.add('hljs');
    codeEl.dataset.highlighted = 'yes';
    did = true;
  });
  return did;
}
function renderFullTwoPhase(md) {
  var gen = ++paintGen;
  deferHighlight = true;
  var html;
  try {
    html = renderMarkdown(md);
  } finally {
    deferHighlight = false;
  }
  var el = document.getElementById('content');
  el.innerHTML = html;
  setTimeout(function() {
    if (gen !== paintGen) return; // 뒤 렌더가 있으면 stale 하이라이트 취소
    if (!el.isConnected) return;
    highlightNow(el);
    // hljs 스팬은 동일 폰트라 높이 불변, 안전망으로 재보고.
    reportHeight();
  }, 0);
}

var streamingState = {
  container: null,
  lastRenderedHTML: '',
  lastStableLength: 0
};

function initStreaming(containerId) {
  streamingState.container = document.getElementById(containerId);
  streamingState.lastRenderedHTML = '';
  streamingState.lastStableLength = 0;
}

function findLastCompleteBlock(markdown) {
  var codeBlocks = markdown.match(/```/g);
  var openCodeBlocks = codeBlocks ? codeBlocks.length % 2 : 0;
  var clean = markdown;
  var codeBlockRegex = /```[\s\S]*?```/g;
  var codeMatch;
  while ((codeMatch = codeBlockRegex.exec(markdown)) !== null) {
    clean = clean.substring(0, codeMatch.index) + ' '.repeat(codeMatch[0].length) + clean.substring(codeMatch.index + codeMatch[0].length);
  }
  var lastComplete = markdown.length;
  if (openCodeBlocks > 0) {
    var lastFence = markdown.lastIndexOf('\n```');
    if (lastFence > 0) {
      lastComplete = lastFence;
    }
  }
  var lines = clean.split('\n');
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i];
    var doubleStars = (line.match(/\*\*/g) || []).length;
    if (doubleStars % 2 !== 0) {
      var beforeLines = lines.slice(0, i).join('\n');
      lastComplete = Math.min(lastComplete, beforeLines.length);
      break;
    }
  }
  return lastComplete;
}

function appendChunk(fullMarkdown) {
  if (!streamingState.container) return;
  var lastComplete = findLastCompleteBlock(fullMarkdown);
  var stablePart = fullMarkdown.substring(0, lastComplete);
  var unstablePart = fullMarkdown.substring(lastComplete);
  var html = '';
  if (stablePart) { html = renderMarkdown(stablePart); }
  if (unstablePart) { html += renderMarkdown(unstablePart); }
  streamingState.container.innerHTML = html;
  streamingState.lastRenderedHTML = html;
  reportHeight();
  scrollToBottom();
}

function finalizeMarkdown() {
  if (!streamingState.container) return;
  var content = streamingState.container.getAttribute('data-full-markdown') || streamingState.container.textContent;
  renderFullTwoPhase(content);
  reportHeight();
  scrollToBottom();
}

// 고정 높이(내부 스크롤) 렌더러에서 스트리밍 중 맨 아래로 자동 스크롤.
// window.__AUTOSCROLL이 true인 경우에만 동작 — 채팅 말풍선(비고정)에는 영향 없음.
function scrollToBottom() {
  if (!window.__AUTOSCROLL) return;
  var scroller = document.scrollingElement || document.documentElement;
  if (scroller && scroller.scrollHeight > scroller.clientHeight) {
    scroller.scrollTop = scroller.scrollHeight;
  }
}

var heightReportTimer = null;
var measureRafId = null;
function reportHeight() {
  if (!streamingState.container) return;
  if (heightReportTimer) clearTimeout(heightReportTimer);
  heightReportTimer = setTimeout(function() { measureStable(); }, 50);
}

function measureStable() {
  if (measureRafId !== null) { cancelAnimationFrame(measureRafId); measureRafId = null; }
  if (!streamingState.container) return;
  var el = streamingState.container;
  var lastH = 0;
  var stableCount = 0;
  var iterations = 0;
  var MAX_ITERATIONS = 15;
  function step() {
    if (!streamingState.container || !el.isConnected) { measureRafId = null; return; }
    iterations++;
    var h = Math.max(el.getBoundingClientRect().height, 40);
    if (h === lastH) {
      stableCount++;
      if (stableCount >= 2 || iterations >= MAX_ITERATIONS) {
        measureRafId = null;
        window.webkit.messageHandlers.heightChange.postMessage(h);
        return;
      }
    } else {
      stableCount = 0;
      lastH = h;
    }
    measureRafId = requestAnimationFrame(step);
  }
  measureRafId = requestAnimationFrame(step);
}

function escapeHtml(text) {
  var div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

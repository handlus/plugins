// 가짜 커서 킷 — 이 파일 내용을 chrome_javascript 의 code 로 그대로 넘긴다.
// (chrome_javascript 는 async 함수 본문으로 실행하므로 맨 끝 최상위 return 이 결과가 된다)
// 여러 번 넣어도 안전하다 — 기존 커서를 지우고 새로 만든다. 페이지를 옮기면 사라지니 다시 넣는다.
//
// 넣은 뒤 쓰는 법 (다른 chrome_javascript 호출에서):
//   const F = window.__fc;
//   F.runAt(Date.now() + 20000, {
//     start: [innerWidth * 0.7, innerHeight * 0.6],        // 커서 시작 위치
//     prep: () => { window.scrollTo(0, 0); },              // 시작 1초 전 — 페이지를 첫 장면으로
//     script: async (F, log) => {                         // 여기에 동작 순서
//       await F.sleep(500);
//       await F.clickEl('summary');                        // 선택자나 요소
//       log('click1');
//     },
//   });
//   // 결과 로그 = window.__fcLog  [[T0 기준 ms, 라벨, document.hidden], …]

document.getElementById('__fc')?.remove();
document.getElementById('__fc_style')?.remove();

const st = document.createElement('style');
st.id = '__fc_style';
st.textContent = `
#__fc{position:fixed;left:0;top:0;z-index:2147483647;pointer-events:none;will-change:transform}
#__fc svg{display:block;transform-origin:3px 3px;filter:drop-shadow(0 2px 3px rgba(0,0,0,.35))}
.__fc_rip{position:fixed;z-index:2147483646;pointer-events:none;width:22px;height:22px;margin:-11px 0 0 -11px;border-radius:50%;border:3px solid #f97316;background:rgba(249,115,22,.22);box-sizing:border-box}`;
document.head.appendChild(st);

const fc = document.createElement('div');
fc.id = '__fc';
// 화살표 끝(3,3)이 클릭 지점
fc.innerHTML = `<svg width="30" height="42" viewBox="0 0 30 42"><path d="M3 3 L3 33 L10.2 26.4 L15 37.4 L20 35.3 L15.3 24.6 L25 24.6 Z" fill="#fff" stroke="#111" stroke-width="2.2" stroke-linejoin="round"/></svg>`;
document.body.appendChild(fc);

const S = { x: innerWidth * 0.7, y: innerHeight * 0.6 };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const $ = el => (typeof el === 'string' ? document.querySelector(el) : el);
const raf = step => new Promise(res => {
  const t0 = performance.now();
  const f = now => (step(now - t0) ? requestAnimationFrame(f) : res());
  requestAnimationFrame(f);
});

function set(x, y) { S.x = x; S.y = y; fc.style.transform = `translate(${x - 3}px,${y - 3}px)`; }

/** 목표까지 살짝 휘며 이동. 거리에 따라 0.4~1초 */
async function moveTo(x, y) {
  const x0 = S.x, y0 = S.y, dx = x - x0, dy = y - y0, d = Math.hypot(dx, dy);
  const dur = Math.min(1000, 420 + d * 0.55), bow = Math.min(60, d * 0.12);
  const nx = -dy / (d || 1), ny = dx / (d || 1);
  await raf(ms => {
    const t = Math.min(1, ms / dur), e = ease(t), b = Math.sin(Math.PI * e) * bow;
    set(x0 + dx * e + nx * b, y0 + dy * e + ny * b);
    return t < 1;
  });
}

/** 누름 — 화살표가 작아졌다 돌아오고 주황 원이 퍼진다. el 이 있으면 110ms 뒤 실제 클릭 */
async function press(el) {
  fc.querySelector('svg').animate(
    [{ transform: 'scale(1)' }, { transform: 'scale(.8)' }, { transform: 'scale(1)' }],
    { duration: 260, easing: 'ease-out' });
  const r = document.createElement('div');
  r.className = '__fc_rip';
  r.style.left = S.x + 'px';
  r.style.top = S.y + 'px';
  document.body.appendChild(r);
  r.animate([{ transform: 'scale(.6)', opacity: 1 }, { transform: 'scale(3.6)', opacity: 0 }],
    { duration: 620, easing: 'cubic-bezier(.2,.7,.3,1)' }).onfinish = () => r.remove();
  await sleep(110);
  if (el) $(el).click();
  await sleep(150);
}

/** 요소 안 클릭 지점 — 가로 fx 비율(최대 260px 안쪽), 세로 가운데 */
function pt(el, fx = 0.35) {
  const b = $(el).getBoundingClientRect();
  return [b.left + Math.min(b.width * fx, 260), b.top + b.height / 2];
}

/** 부드러운 스크롤 (마우스 휠처럼) */
async function scrollBy(dy, dur = 700) {
  document.documentElement.style.scrollBehavior = 'auto';
  const y0 = scrollY;
  await raf(ms => { const t = Math.min(1, ms / dur); window.scrollTo(0, y0 + dy * ease(t)); return t < 1; });
}

/** 화면 아래를 덮는 고정 요소(신청 바·쿠키 배너 등)의 윗선 */
function barTop() {
  for (const el of document.elementsFromPoint(innerWidth / 2, innerHeight - 40)) {
    for (let e = el; e && e !== document.body; e = e.parentElement) {
      const p = getComputedStyle(e).position;
      if ((p === 'fixed' || p === 'sticky') && e.id !== '__fc') return e.getBoundingClientRect().top;
    }
  }
  return innerHeight;
}

/** 요소가 가려져 있거나 화면 밖이면 위에서 190px 자리로 부드럽게 스크롤 */
async function ensure(el) {
  const b = $(el).getBoundingClientRect();
  if (b.bottom > barTop() - 60 || b.top < 90) await scrollBy(b.top - 190, 650);
}

/** 보이게 스크롤 → 이동 → 잠깐 멈춤 → 누름+클릭 */
async function clickEl(el, fx) {
  el = $(el);
  if (!el) throw new Error('clickEl: 요소 없음');
  await ensure(el);
  const [x, y] = pt(el, fx);
  await moveTo(x, y);
  await sleep(160);
  await press(el);
}

/** 입력칸에 한 글자씩 — React 가 값 변화를 알아채게 네이티브 setter + input 이벤트 */
async function typeInto(el, text, msPer = 70) {
  el = $(el);
  el.focus();
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
  for (const ch of text) {
    setter.call(el, el.value + ch);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    await sleep(msPer);
  }
}

/** contenteditable(ProseMirror 등 — claude.ai 채팅 입력창)에 한 글자씩. typeInto 는 input·textarea 전용이라 여기엔 안 들어간다 */
async function typeCE(el, text, msPer = 70) {
  el = $(el);
  el.focus();
  const sel = getSelection(); sel.selectAllChildren(el); sel.collapseToEnd();
  for (const ch of text) {
    document.execCommand('insertText', false, ch);
    await sleep(msPer);
  }
}

/** 첫 장면 정리 — 남은 글자 선택(녹화에 파랗게 찍힌다)·포커스를 지우고 커서를 시작 위치로 */
function reset(start) {
  getSelection().removeAllRanges();
  document.activeElement?.blur?.();
  if (start) set(start[0], start[1]);
}

/** T0 에 script 를 실행하도록 예약. 시작 1초 전에 prep + reset. 모든 단계가 __fcLog 에 남는다 */
function runAt(T0, { start, prep, script }) {
  window.__fcLog = [];
  // 페이지를 넘기는 클릭으로 끝나는 테이크는 로그가 페이지와 같이 사라진다 → 같은 사이트의 localStorage 에도 쓴다.
  // 넘어간 뒤에는 그 사이트를 다시 열어 localStorage.__fcLog 를 읽는다 (2026-10-13)
  const log = m => { window.__fcLog.push([Date.now() - T0, m, document.hidden]); try { localStorage.setItem('__fcLog', JSON.stringify({ T0, log: window.__fcLog })); } catch (e) {} };
  setTimeout(() => { try { prep && prep(); } catch (e) { log('prep error ' + e.message); } reset(start); },
    Math.max(0, T0 - Date.now() - 1000));
  setTimeout(async () => {
    log('start');
    try { await script(window.__fc, log); } catch (e) { log('error ' + e.message); }
    log('end');
  }, T0 - Date.now());
  return T0;
}

window.__fc = { set, moveTo, press, pt, clickEl, scrollBy, ensure, barTop, typeInto, typeCE, reset, runAt, sleep, remove() {
  fc.remove(); st.remove(); delete window.__fc;
} };
set(S.x, S.y);
return { ok: true, viewport: [innerWidth, innerHeight], dpr: devicePixelRatio, screen: [screenX, screenY] };

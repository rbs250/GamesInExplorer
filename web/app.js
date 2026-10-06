'use strict';
const $ = id => document.getElementById(id);
let games = [], filtered = [], selected = 0, mode = localStorage.getItem('view') || 'flow';
let toastTimer, wheelTime = 0, launchTime = 0, busy = false;
let catalog = {}, infoGameId = null;
const bridge = window.chrome?.webview;
const isInstalled = game => game.installed !== false;
const gameState = game => isInstalled(game) ? 'Installed' : 'Not installed';
const gameLabel = game => `Select ${game.name}${isInstalled(game) ? '' : ', Not installed'}`;
function toast(message) { ($('game-box').open ? $('game-box') : document.body).append($('toast')); $('toast').textContent = message; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 4200); }
function send(message) { if (bridge) bridge.postMessage(message); else toast('Open the Games folder in Windows Explorer to use this action.'); }
function artwork(game, className) {
  const element = document.createElement(game.cover ? 'img' : 'div');
  element.className = className;
  if (game.cover) { element.src = game.cover; element.alt = ''; element.draggable = false; element.addEventListener('error', () => { element.replaceWith(artwork({...game, cover:''}, className)); }, {once:true}); }
  else { element.classList.add('fallback-art'); const title = document.createElement('strong'); title.textContent = game.name; element.append(title); }
  return element;
}
async function load(keep = true) {
  try {
    let response = await fetch(`library.json?t=${Date.now()}`, {cache:'no-store'});
    if (response.status === 404) response = await fetch('library.template.json', {cache:'no-store'});
    if (!response.ok) throw new Error('Library not available');
    const data = await response.json();
    if (!Array.isArray(data.games)) throw new Error('Library not readable');
    try {
      let details = await fetch(`game-details.json?t=${Date.now()}`, {cache:'no-store'});
      if (details.status === 404) details = await fetch('game-details.template.json', {cache:'no-store'});
      if (details.ok) catalog = await details.json();
    } catch (_) { /* The installed library remains usable without its optional catalog. */ }
    const current = keep && filtered[selected]?.id;
    games = data.games;
    $('library-count').textContent = `${games.length} games · ${games.filter(isInstalled).length} installed`;
    filter(current || localStorage.getItem('selection'));
    if ($('game-box').open && infoGameId) fillInfo(infoGameId);
    return true;
  } catch (error) {
    if (games.length) {
      toast('Could not refresh the library. Your previous library is still available.');
      return false;
    }
    $('library-count').textContent = 'Library unavailable';
    $('empty').hidden = false; $('empty').querySelector('h2').textContent = 'Let’s find your games';
    $('empty').querySelector('p').textContent = 'Use Refresh to scan your installed games.';
    $('details').hidden = true; $('previous').hidden = true; $('next').hidden = true;
    return false;
  }
}
function filter(preferredId) {
  const query = $('search').value.trim().toLocaleLowerCase();
  const oldId = preferredId || filtered[selected]?.id;
  filtered = games.filter(game => game.name.toLocaleLowerCase().includes(query));
  const found = filtered.findIndex(game => game.id === oldId);
  selected = found >= 0 ? found : Math.floor(filtered.length / 2);
  render();
}
function render() {
  $('covers').replaceChildren(); $('filmstrip').replaceChildren(); $('grid').replaceChildren();
  const hasGames = filtered.length > 0;
  $('empty').hidden = hasGames;
  $('empty').querySelector('h2').textContent = games.length ? 'No matching games' : 'Your collection starts here';
  $('empty').querySelector('p').textContent = games.length ? 'Try another title or clear your search.' : 'Refresh to find installed games, or use + to add one.';
  $('clear-search').hidden = !$('search').value;
  $('details').hidden = !hasGames;
  $('previous').hidden = $('next').hidden = filtered.length < 2;
  filtered.forEach((game, i) => {
    const cover = document.createElement('button'); cover.className = 'cover'; cover.dataset.index = i;
    cover.classList.toggle('uninstalled', !isInstalled(game));
    cover.setAttribute('aria-label', gameLabel(game)); cover.tabIndex = -1;
    cover.append(artwork(game, 'art'));
    if (game.cover) { const reflection = artwork(game, 'reflection'); reflection.setAttribute('aria-hidden','true'); cover.append(reflection); }
    cover.onclick = () => select(i); cover.ondblclick = () => { select(i); play(); };
    $('covers').append(cover);
    const mini = document.createElement('button'); mini.className = 'mini'; mini.classList.toggle('uninstalled', !isInstalled(game)); mini.title = `${game.name} · ${gameState(game)}`; mini.setAttribute('aria-label', gameLabel(game));
    if (game.cover) mini.append(artwork(game,'')); else { const mark = document.createElement('span'); mark.className = 'mini-fallback'; mark.textContent = game.name.slice(0,2); mini.append(mark); }
    mini.onclick = () => select(i); $('filmstrip').append(mini);
    const card = document.createElement('button'); card.className = 'grid-card'; card.classList.toggle('uninstalled', !isInstalled(game)); card.setAttribute('aria-label', gameLabel(game));
    card.append(artwork(game,'grid-art'));
    const title = document.createElement('span'); title.className = 'grid-title'; title.textContent = game.name;
    const platform = document.createElement('span'); platform.className = 'grid-platform'; platform.textContent = `${game.platform} · ${gameState(game)}`;
    card.append(title,platform); card.onclick = () => { setMode('flow'); select(i); }; $('grid').append(card);
  });
  setMode(mode); updateSelection();
}
function select(index) {
  if (!filtered.length) return;
  selected = (index + filtered.length) % filtered.length;
  localStorage.setItem('selection', filtered[selected].id);
  updateSelection();
}
function updateSelection() {
  const game = filtered[selected], count = filtered.length;
  $('position').textContent = count ? `${String(selected+1).padStart(2,'0')} / ${String(count).padStart(2,'0')}` : '0 games';
  if (!game) return;
  layoutShelf();
  const coverWidth = $('covers').firstElementChild?.offsetWidth || 200;
  [...$('covers').children].forEach((cover,i) => {
    let d = i - selected;
    if (d > count/2) d -= count; if (d < -count/2) d += count;
    const a = Math.abs(d), direction = Math.sign(d);
    const x = direction * (a ? coverWidth*.98 + (a-1)*coverWidth*.49 : 0);
    cover.style.transform = `translate(-50%, -50%) translateX(${x}px) translateZ(${-a*65}px) rotateY(${-direction * (a ? 54 : 0)}deg)`;
    cover.style.zIndex = String(50-a); cover.style.opacity = a>4 ? '0' : '1'; cover.style.visibility = a>4 ? 'hidden':'visible';
    cover.classList.toggle('selected',i === selected); cover.setAttribute('aria-pressed',String(i === selected));
  });
  [...$('filmstrip').children].forEach((mini,i) => { mini.classList.toggle('active',i === selected); mini.setAttribute('aria-pressed',String(i === selected)); });
  if (mode === 'flow') $('filmstrip').children[selected]?.scrollIntoView({block:'nearest',inline:'nearest'});
  $('game-title').textContent = game.name;
  $('platform').textContent = `${game.platform} · ${gameState(game)}`;
  $('details').classList.toggle('uninstalled', !isInstalled(game));
  $('size').textContent = isInstalled(game) && game.sizeGB ? `${game.sizeGB} GB` : '';
  $('play').querySelector('span').textContent = isInstalled(game) ? 'Play' : 'Install in Steam';
  $('play').querySelector('use').setAttribute('href', isInstalled(game) ? '#play-icon' : '#plus-icon');
  $('play').setAttribute('aria-label', `${isInstalled(game) ? 'Play' : 'Install in Steam'} ${game.name}`);
  $('open-folder').hidden = !isInstalled(game);
  $('open-folder').disabled = !isInstalled(game);
  $('keyboard-action').textContent = isInstalled(game) ? 'Play' : 'Install';
}
function setMode(value) {
  mode = value === 'grid' ? 'grid' : 'flow'; localStorage.setItem('view',mode);
  document.body.classList.toggle('grid-mode',mode === 'grid'); $('grid').hidden = mode !== 'grid';
  $('grid-size-control').hidden = mode !== 'grid';
  ['flow','grid'].forEach(v => { $(`${v}-view`).classList.toggle('active',mode === v); $(`${v}-view`).setAttribute('aria-pressed',String(mode === v)); });
  if (mode === 'flow') requestAnimationFrame(updateSelection);
}
function layoutShelf() {
  const shelf = $('shelf');
  if (!shelf.clientHeight || mode === 'grid') return;
  // Reserve 40% of the artwork height for the reflection to reach zero opacity.
  const height = Math.max(24, Math.min(440, (shelf.clientHeight - 28) / 1.4, (shelf.clientWidth - 64) * .95));
  const top = Math.max(8, (shelf.clientHeight - height * 1.4 - 7) / 2) + height / 2;
  document.documentElement.style.setProperty('--cover-height',`${height}px`);
  document.documentElement.style.setProperty('--cover-top',`${top}px`);
}
function setGridSize(value) {
  const number = Number(value);
  const width = Math.round(Math.min(260, Math.max(110, Number.isFinite(number) && number ? number : 160)) / 10) * 10;
  $('grid-size').value = String(width);
  document.documentElement.style.setProperty('--grid-cover-width', `${width}px`);
  $('grid-size-value').value = `${Math.round(width / 160 * 100)}%`;
  localStorage.setItem('grid-size', String(width));
}
function fillInfo(id) {
  const game = games.find(g => g.id === id);
  if (!game) { $('game-box').close(); return; }
  const info = catalog[id] || {};
  $('box-title').textContent = game.name;
  $('box-cover').classList.toggle('uninstalled', !isInstalled(game));
  $('box-cover').replaceChildren(artwork(game,'art'));
  $('box-synopsis').textContent = info.synopsis || (isInstalled(game)
    ? 'This game is installed and ready to play. Detailed game information has not been added to this library yet.'
    : 'This game is in your Steam library but is not installed on this PC. Detailed game information has not been added to this library yet.');
  $('box-screenshots').replaceChildren();
  (info.screenshots || []).slice(0,2).forEach((path,index) => {
    const img = document.createElement('img'); img.src = path; img.alt = `${game.name} — gameplay screenshot ${index+1}`;
    img.onerror = () => img.remove(); $('box-screenshots').append(img);
  });
  $('box-features').replaceChildren();
  (info.features || []).forEach(text => { const li = document.createElement('li'); li.textContent = text; $('box-features').append(li); });
  $('box-facts').replaceChildren();
  const facts = [['Developer',info.developer],['Publisher',info.publisher],[game.platform === 'Steam' ? 'Steam release' : 'Release',info.release],['Genre',info.genre],['Players',info.players],[isInstalled(game) ? 'On your PC' : 'Installation',`${game.platform} · ${gameState(game)}${isInstalled(game) && game.sizeGB ? ` · ${game.sizeGB} GB` : ''}`]];
  facts.forEach(([label,value]) => {
    if (!value) return;
    const row = document.createElement('div'), term = document.createElement('dt'), definition = document.createElement('dd');
    term.textContent = label; definition.textContent = value; row.append(term,definition); $('box-facts').append(row);
  });
  $('cover-credit').textContent = game.customCover ? 'Your custom cover' : info.coverCredit || (game.cover ? 'Cover artwork from your local library.' : 'Add a portrait image to complete this box.');
  $('change-cover').querySelector('span').textContent = game.cover ? 'Change cover' : 'Add cover';
  $('box-source').hidden = !info.sourceUrl && game.platform !== 'Steam';
  $('box-source').querySelector('span').textContent = game.platform === 'Steam' ? 'View on Steam' : 'View project';
  $('box-source-note').textContent = info.sourceUrl ? 'Game details from the official store or project. Saved for offline browsing.' : (game.platform === 'Steam' ? 'Open this game’s Steam page.' : 'Install details from this PC.');
}
function showInfo() {
  if (!filtered[selected]) return;
  infoGameId = filtered[selected].id;
  fillInfo(infoGameId); $('game-box').showModal(); $('game-box').scrollTop = 0;
  $('close-info').focus();
}
function changeCover() {
  if (busy || !infoGameId) return;
  busy = true; $('change-cover').disabled = $('refresh').disabled = $('add').disabled = true;
  send(`artwork:${infoGameId}`);
  if (!bridge) resetBusy();
}
function play() {
  if (!filtered[selected] || Date.now()-launchTime < 1600) return;
  launchTime = Date.now(); send(`launch:${filtered[selected].id}`);
}
function scan(add = false) {
  if (busy) return; busy = true; $('refresh').classList.add('busy'); $('refresh').disabled = $('add').disabled = true;
  send(add ? 'add' : 'refresh');
  if (!bridge) resetBusy();
}
function resetBusy() { busy = false; $('refresh').classList.remove('busy'); $('refresh').disabled = $('add').disabled = $('change-cover').disabled = false; }
$('search').oninput = () => filter();
$('clear-search').onclick = () => { $('search').value = ''; filter(); $('search').focus(); };
$('flow-view').onclick = () => setMode('flow'); $('grid-view').onclick = () => setMode('grid');
$('previous').onclick = () => select(selected-1); $('next').onclick = () => select(selected+1);
$('play').onclick = play; $('open-folder').onclick = () => { if (filtered[selected] && isInstalled(filtered[selected])) send(`folder:${filtered[selected].id}`); };
$('game-info').onclick = showInfo; $('close-info').onclick = () => $('game-box').close();
$('game-box').addEventListener('close',() => { infoGameId = null; document.body.append($('toast')); $('game-info').focus(); });
$('change-cover').onclick = changeCover;
$('box-source').onclick = () => { if (infoGameId) send(`source:${infoGameId}`); };
$('grid-size').oninput = e => setGridSize(e.target.value);
setGridSize(localStorage.getItem('grid-size'));
$('refresh').onclick = () => scan(); $('add').onclick = () => scan(true);
document.addEventListener('keydown',e => {
  if ($('game-box').open) return;
  if (e.target instanceof HTMLInputElement) { if (e.target === $('search') && e.key === 'Escape') { $('search').value = ''; filter(); $('shelf').focus(); } return; }
  if (e.altKey || e.ctrlKey || e.metaKey) return;
  if (e.key === '/') { e.preventDefault(); $('search').focus(); }
  if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') { e.preventDefault(); select(selected+(e.key === 'ArrowRight' ? 1:-1)); }
  if (e.key === 'Home') { e.preventDefault(); select(0); }
  if (e.key === 'End') { e.preventDefault(); select(filtered.length-1); }
  if (e.key === 'Enter' && (e.target === document.body || e.target === $('shelf'))) { e.preventDefault(); play(); }
});
$('shelf').addEventListener('wheel',e => { if (Math.abs(e.deltaY)+Math.abs(e.deltaX)<3) return; e.preventDefault(); if (Date.now()-wheelTime>220) { select(selected+((e.deltaX||e.deltaY)>0 ? 1:-1)); wheelTime=Date.now(); } },{passive:false});
let dragX = null;
$('shelf').addEventListener('pointerdown',e => dragX=e.clientX);
$('shelf').addEventListener('pointerup',e => { if (dragX !== null && Math.abs(e.clientX-dragX)>50) select(selected+(e.clientX<dragX ? 1:-1)); dragX=null; });
window.addEventListener('resize',updateSelection);
new ResizeObserver(() => { if (mode === 'flow') updateSelection(); }).observe($('shelf'));
window.nativeMessage = e => {
  if (e.data === 'refreshed') { resetBusy(); load().then(ok => { if (ok) toast('Library refreshed'); }); }
  else if (e.data === 'artwork-updated') { resetBusy(); load().then(ok => { if (ok) toast('Cover updated'); }); }
  else if (e.data === 'cancelled') resetBusy();
  else if (e.data === 'launched') toast(`Opening ${filtered[selected]?.name || 'game'}…`);
  else if (e.data === 'install-requested') toast('Opening Steam’s installer for this game…');
  else if (typeof e.data === 'string' && e.data.startsWith('error:')) { resetBusy(); toast(e.data.slice(6)); }
};
bridge?.addEventListener('message',window.nativeMessage);
load(false);

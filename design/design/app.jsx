// app.jsx — root of GitForge

const { useState: useS, useEffect: useE, useRef: useR, useCallback: useC } = React;

// ─── Command Palette (⌘K) ─────────────────────────────────────────────
function CommandPalette({ open, onClose, onAction, repos, onRepoChange, onView }) {
  const [q, setQ] = useS('');
  const [idx, setIdx] = useS(0);
  const inputRef = useR(null);

  useE(() => { if (open) { setQ(''); setIdx(0); setTimeout(() => inputRef.current?.focus(), 30); } }, [open]);

  const items = React.useMemo(() => {
    const all = [
      ...repos.map(r => ({ kind: 'repo', label: `${r.org}/${r.name}`, hint: r.branch, action: () => onRepoChange(r) })),
      ...COMMITS.slice(0, 12).map(c => ({ kind: 'commit', label: c.msg, hint: c.sha, action: () => onView('graph') })),
      ...BRANCHES.map(b => ({ kind: 'branch', label: b.name, hint: b.type, action: () => onView('branches') })),
      ...WORKING_FILES.map(f => ({ kind: 'file', label: f.path, hint: f.status, action: () => onView('staging') })),
      { kind: 'cmd', label: 'Fetch all',  hint: '⇧⌘F', action: () => onAction('fetch') },
      { kind: 'cmd', label: 'Pull',       hint: '⌘⇧P', action: () => onAction('pull') },
      { kind: 'cmd', label: 'Push',       hint: '⌘⇧K', action: () => onAction('push') },
      { kind: 'cmd', label: 'New branch…', hint: '⌘⇧B', action: () => onView('branches') },
      { kind: 'cmd', label: 'Stash changes', hint: '',  action: () => onAction('stash') },
      { kind: 'cmd', label: 'Open terminal', hint: '⌃`', action: () => onView('terminal') },
      { kind: 'cmd', label: 'Settings',    hint: '⌘,',  action: () => onView('settings') },
    ];
    if (!q) return all.slice(0, 12);
    const ql = q.toLowerCase();
    return all.filter(it => it.label.toLowerCase().includes(ql) || it.hint?.toLowerCase().includes(ql)).slice(0, 16);
  }, [q, repos]);

  if (!open) return null;

  const onKey = (e) => {
    if (e.key === 'Escape') onClose();
    else if (e.key === 'ArrowDown') { e.preventDefault(); setIdx(i => Math.min(items.length - 1, i + 1)); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setIdx(i => Math.max(0, i - 1)); }
    else if (e.key === 'Enter') { items[idx]?.action(); onClose(); }
  };

  const kindMeta = {
    repo:   { icon: I.folder, label: 'Repo' },
    commit: { icon: I.diamond, label: 'Commit' },
    branch: { icon: I.branch, label: 'Branch' },
    file:   { icon: I.diff, label: 'File' },
    cmd:    { icon: I.cmd, label: 'Command' },
  };

  return (
    <div className="gf-cmdk-backdrop" onClick={onClose}>
      <div className="gf-cmdk" onClick={e => e.stopPropagation()}>
        <div className="gf-cmdk-input-row">
          <span className="gf-cm-icon">{I.search}</span>
          <input ref={inputRef} className="gf-cmdk-input" placeholder="Search repos, commits, branches, files…"
                 value={q} onChange={e => { setQ(e.target.value); setIdx(0); }} onKeyDown={onKey} />
          <kbd>esc</kbd>
        </div>
        <div className="gf-cmdk-list">
          {items.length === 0 && <div className="gf-cmdk-empty">No matches for “{q}”</div>}
          {items.map((it, i) => (
            <button key={i} className={`gf-cmdk-row ${i === idx ? 'is-active' : ''}`}
                    onMouseEnter={() => setIdx(i)}
                    onClick={() => { it.action(); onClose(); }}>
              <span className="gf-cmdk-kind">{kindMeta[it.kind].icon}</span>
              <span className="gf-cmdk-label">{it.label}</span>
              <span className="gf-cmdk-tag">{kindMeta[it.kind].label}</span>
              {it.hint && <span className="gf-cmdk-hint gf-mono">{it.hint}</span>}
            </button>
          ))}
        </div>
        <div className="gf-cmdk-foot">
          <span><kbd>↑↓</kbd> navigate</span>
          <span><kbd>↵</kbd> select</span>
          <span><kbd>esc</kbd> close</span>
        </div>
      </div>
    </div>
  );
}

// ─── Toast ────────────────────────────────────────────────────────────
function Toast({ message, kind = 'info', onClose }) {
  useE(() => { const t = setTimeout(onClose, 2400); return () => clearTimeout(t); }, [onClose]);
  return (
    <div className={`gf-toast gf-toast-${kind}`}>
      <span className="gf-cm-icon">{kind === 'ok' ? I.check : I.dot}</span>
      <span>{message}</span>
    </div>
  );
}

// ─── App ──────────────────────────────────────────────────────────────
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "accent": "#7c5cff",
  "density": "regular",
  "showFileTree": true,
  "monoFont": "JetBrains Mono"
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [view, setView] = useS('graph');
  const [repo, setRepo] = useS(REPOS[0]);
  const [cmdkOpen, setCmdkOpen] = useS(false);
  const [toast, setToast] = useS(null);

  // ⌘K binding
  useE(() => {
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') { e.preventDefault(); setCmdkOpen(true); }
      if (e.key === 'Escape') setCmdkOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const action = useC((kind) => {
    const map = {
      fetch: 'Fetched 3 remotes',
      pull:  'Pulled 1 commit from origin/main',
      push:  'Pushed 7 commits to origin/feat/commit-graph',
      stash: 'Stashed changes (stash@{0})',
    };
    setToast({ message: map[kind] || 'Done', kind: 'ok' });
  }, []);

  // Apply theme + accent + density to root
  useE(() => {
    document.documentElement.dataset.theme = t.theme;
    document.documentElement.dataset.density = t.density;
    document.documentElement.style.setProperty('--accent', t.accent);
    document.documentElement.style.setProperty('--mono-font', `"${t.monoFont}", ui-monospace, monospace`);
  }, [t.theme, t.accent, t.density, t.monoFont]);

  const screens = {
    graph:    <HistoryView density={t.density} onView={setView} />,
    staging:  <StagingView />,
    branches: <BranchesView />,
    pulls:    <PullsView />,
    conflict: <ConflictView />,
    blame:    <BlameView />,
    clone:    <CloneView />,
    settings: <SettingsView />,
    terminal: <TerminalView />,
  };

  return (
    <div className="gf-app" data-screen-label={`GitForge · ${view}`}>
      <GFWindow title={`${repo.org}/${repo.name} — GitForge`}>
        <div className="gf-shell">
          <Sidebar repos={REPOS} currentRepo={repo} onRepoChange={setRepo}
                   view={view} onView={setView}
                   onOpenSearch={() => setCmdkOpen(true)} />
          <main className="gf-main">{screens[view]}</main>
        </div>
        <div className="gf-statusbar">
          <span className="gf-mono"><span className="gf-cm-icon">{I.branch}</span> feat/commit-graph</span>
          <span className="gf-mono"><span className="gf-stat-up">↑7</span><span className="gf-stat-dn">↓1</span></span>
          <span className="gf-mono">3 staged · 4 unstaged</span>
          <div style={{ flex: 1 }} />
          <span className="gf-mono gf-dim">last fetch · 2m ago</span>
          <span className="gf-mono gf-dim">UTF-8</span>
          <span className="gf-mono gf-dim">LF</span>
          <span className="gf-mono">
            <span className="gf-stat-dot" style={{ background: 'var(--ok)' }} />
            online
          </span>
        </div>
      </GFWindow>

      <CommandPalette open={cmdkOpen} onClose={() => setCmdkOpen(false)}
                      onAction={action} repos={REPOS}
                      onRepoChange={(r) => setRepo(r)} onView={setView} />

      {toast && <Toast {...toast} onClose={() => setToast(null)} />}

      <TweaksPanel>
        <TweakSection label="Appearance" />
        <TweakRadio label="Theme" value={t.theme} options={['dark', 'light']}
                    onChange={(v) => setTweak('theme', v)} />
        <TweakColor label="Accent" value={t.accent}
                    options={['#7c5cff', '#56b497', '#ff7e6b', '#5da4ff']}
                    onChange={(v) => setTweak('accent', v)} />
        <TweakRadio label="Density" value={t.density}
                    options={['compact', 'regular', 'comfy']}
                    onChange={(v) => setTweak('density', v)} />
        <TweakSection label="Code" />
        <TweakSelect label="Mono font" value={t.monoFont}
                     options={['JetBrains Mono', 'IBM Plex Mono', 'Fira Code', 'SF Mono']}
                     onChange={(v) => setTweak('monoFont', v)} />
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

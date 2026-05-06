// screens-other.jsx — Staging, Branches, Pulls, Conflicts, Blame, Clone, Settings, Terminal

const { useState: uS } = React;

// ─── Staging / Changes ────────────────────────────────────────────────
function StagingView() {
  const [files, setFiles] = uS(WORKING_FILES);
  const [selected, setSelected] = uS(files[0].path);
  const [msg, setMsg] = uS('');
  const [desc, setDesc] = uS('');
  const staged = files.filter(f => f.staged);
  const unstaged = files.filter(f => !f.staged);
  const sel = files.find(f => f.path === selected);

  const toggle = (path) => setFiles(fs => fs.map(f => f.path === path ? { ...f, staged: !f.staged } : f));
  const stageAll = () => setFiles(fs => fs.map(f => ({ ...f, staged: true })));
  const unstageAll = () => setFiles(fs => fs.map(f => ({ ...f, staged: false })));

  return (
    <div className="gf-view-staging">
      <ContentHeader
        title="Changes"
        subtitle={<span className="gf-mono">{staged.length} staged · {unstaged.length} unstaged</span>}
        right={
          <div className="gf-content-actions">
            <ToolButton icon={I.stash} label="Stash" />
            <ToolButton icon={I.x} label="Discard all" />
          </div>
        }
      />

      <div className="gf-staging-grid">
        <div className="gf-files-col">
          <div className="gf-files-section">
            <div className="gf-files-h">
              <span>Staged <span className="gf-dim">({staged.length})</span></span>
              <button className="gf-mini-action" onClick={unstageAll}>Unstage all</button>
            </div>
            {staged.length === 0 && <div className="gf-files-empty">Nothing staged</div>}
            {staged.map(f => (
              <FileRow key={f.path} file={f} selected={selected === f.path}
                       onSelect={() => setSelected(f.path)} onToggle={() => toggle(f.path)} />
            ))}
          </div>

          <div className="gf-files-section">
            <div className="gf-files-h">
              <span>Unstaged <span className="gf-dim">({unstaged.length})</span></span>
              <button className="gf-mini-action" onClick={stageAll}>Stage all</button>
            </div>
            {unstaged.map(f => (
              <FileRow key={f.path} file={f} selected={selected === f.path}
                       onSelect={() => setSelected(f.path)} onToggle={() => toggle(f.path)} />
            ))}
          </div>

          <div className="gf-commit-box">
            <input className="gf-commit-msg" placeholder="Commit message"
                   value={msg} onChange={e => setMsg(e.target.value)} />
            <textarea className="gf-commit-desc" placeholder="Description (optional)"
                      value={desc} onChange={e => setDesc(e.target.value)} rows={3} />
            <div className="gf-commit-foot">
              <span className="gf-mono gf-dim">on feat/commit-graph · {staged.length} files</span>
              <div className="gf-commit-actions">
                <button className="gf-btn">Commit & push</button>
                <button className="gf-btn gf-btn-primary" disabled={!msg || staged.length === 0}>
                  Commit
                </button>
              </div>
            </div>
            <button className="gf-suggest">
              <span className="gf-cm-icon">{I.cmd}</span>
              Suggest commit message
            </button>
          </div>
        </div>

        <div className="gf-diff-col">
          {sel && <DiffPane file={sel.path} hunks={DIFF_HUNKS} viewMode="unified" />}
        </div>
      </div>
    </div>
  );
}

function FileRow({ file, selected, onSelect, onToggle }) {
  return (
    <div className={`gf-file-row ${selected ? 'is-selected' : ''}`} onClick={onSelect}>
      <input type="checkbox" checked={file.staged} onChange={onToggle} onClick={e => e.stopPropagation()} />
      <span className={`gf-status-tag gf-status-${file.status}`}>{file.status}</span>
      <span className="gf-file-path">
        <span className="gf-file-dir">{file.path.split('/').slice(0, -1).join('/')}/</span>
        <span className="gf-file-name">{file.path.split('/').slice(-1)}</span>
      </span>
      <span className="gf-file-stats">
        {file.added > 0 && <span className="gf-add">+{file.added}</span>}
        {file.removed > 0 && <span className="gf-del">−{file.removed}</span>}
      </span>
    </div>
  );
}

// ─── Branches ─────────────────────────────────────────────────────────
function BranchesView() {
  const [filter, setFilter] = uS('');
  const local = BRANCHES.filter(b => b.type === 'local' && b.name.includes(filter));
  const remote = BRANCHES.filter(b => b.type === 'remote' && b.name.includes(filter));
  return (
    <div className="gf-view-branches">
      <ContentHeader title="Branches"
        right={
          <div className="gf-content-actions">
            <input className="gf-input" placeholder="Filter branches…" value={filter}
                   onChange={e => setFilter(e.target.value)} style={{ width: 220 }} />
            <ToolButton icon={I.plus} label="New branch" primary />
          </div>
        }
      />
      <div className="gf-branches-wrap">
        <BranchSection title="Local" items={local} />
        <BranchSection title="Remote" items={remote} />
        <div className="gf-branch-section">
          <div className="gf-branch-section-h">Tags</div>
          <div className="gf-tag-row">
            {TAGS.map(t => <span key={t} className="gf-tag">{I.diamond}{t}</span>)}
          </div>
        </div>
      </div>
    </div>
  );
}

function BranchSection({ title, items }) {
  return (
    <div className="gf-branch-section">
      <div className="gf-branch-section-h">{title} <span className="gf-dim">{items.length}</span></div>
      <table className="gf-branch-table">
        <thead>
          <tr><th></th><th>Name</th><th>Last commit</th><th>Sync</th><th></th></tr>
        </thead>
        <tbody>
          {items.map(b => (
            <tr key={b.name} className={b.current ? 'is-current' : ''}>
              <td>{b.current && <span className="gf-cur-dot" />}</td>
              <td className="gf-mono">
                <span className="gf-cm-icon" style={{ marginRight: 6 }}>{I.branch}</span>
                {b.name}
                {b.current && <span className="gf-pill gf-pill-clean" style={{ marginLeft: 8 }}>HEAD</span>}
              </td>
              <td className="gf-dim">{b.lastCommit}</td>
              <td><StatusPill ahead={b.ahead} behind={b.behind} /></td>
              <td className="gf-row-actions">
                {!b.current && <button className="gf-btn gf-btn-sm">Checkout</button>}
                <button className="gf-icon-btn">{I.more}</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ─── Pull requests ────────────────────────────────────────────────────
function PullsView() {
  const [tab, setTab] = uS('open');
  const filtered = PULLS.filter(p => tab === 'all' ? true : tab === 'open' ? p.status === 'open' || p.status === 'review' : p.status === tab);
  const [selected, setSelected] = uS(filtered[0]?.num);
  const sel = PULLS.find(p => p.num === selected);

  return (
    <div className="gf-view-pulls">
      <ContentHeader title="Pull requests"
        right={
          <div className="gf-content-actions">
            <div className="gf-segmented">
              <button className={tab === 'open' ? 'is-active' : ''} onClick={() => setTab('open')}>Open</button>
              <button className={tab === 'merged' ? 'is-active' : ''} onClick={() => setTab('merged')}>Merged</button>
              <button className={tab === 'all' ? 'is-active' : ''} onClick={() => setTab('all')}>All</button>
            </div>
            <ToolButton icon={I.plus} label="New PR" primary />
          </div>
        }
      />
      <div className="gf-pulls-grid">
        <div className="gf-pulls-list">
          {filtered.map(p => (
            <button key={p.num} className={`gf-pr-row ${selected === p.num ? 'is-selected' : ''}`}
                    onClick={() => setSelected(p.num)}>
              <span className={`gf-pr-status gf-pr-${p.status}`}>
                {p.status === 'merged' ? '◆' : p.status === 'review' ? '◐' : '○'}
              </span>
              <div className="gf-pr-text">
                <div className="gf-pr-title">{p.title}</div>
                <div className="gf-pr-meta gf-mono">
                  #{p.num} · {p.author} · {p.branch} → {p.target} · {p.when}
                </div>
              </div>
              <div className="gf-pr-side">
                <span className={`gf-pr-checks gf-checks-${p.checks}`}>
                  {p.checks === 'pass' ? '✓' : p.checks === 'running' ? '●' : '✕'}
                </span>
                <span className="gf-pr-reviews">{p.reviews}/2</span>
              </div>
            </button>
          ))}
        </div>
        <div className="gf-pr-detail">
          {sel && <>
            <div className="gf-pr-d-h">
              <span className={`gf-pr-status gf-pr-${sel.status}`} style={{ fontSize: 18 }}>
                {sel.status === 'merged' ? '◆' : '○'}
              </span>
              <h2 className="gf-h2">{sel.title}</h2>
              <span className="gf-mono gf-dim">#{sel.num}</span>
            </div>
            <div className="gf-pr-d-meta gf-mono">
              <Avatar name={sel.author} size={18} /> {sel.author} wants to merge
              <span className="gf-pill gf-pill-up">{sel.branch}</span>
              into
              <span className="gf-pill gf-pill-clean">{sel.target}</span>
            </div>
            <div className="gf-pr-d-section">
              <div className="gf-pr-d-h2">Checks</div>
              <div className="gf-checks-list">
                <CheckRow name="lint"     status="pass"    time="2m 14s" />
                <CheckRow name="test:unit" status="pass"   time="4m 02s" />
                <CheckRow name="test:e2e"  status="running" time="2m 18s" />
                <CheckRow name="build"    status="pass"    time="1m 42s" />
              </div>
            </div>
            <div className="gf-pr-d-section">
              <div className="gf-pr-d-h2">Reviewers</div>
              <div className="gf-reviewers">
                <ReviewerRow name="L. Park" approved />
                <ReviewerRow name="R. Tanaka" pending />
              </div>
            </div>
            <div className="gf-pr-d-actions">
              <button className="gf-btn">Add review</button>
              <button className="gf-btn">Checkout PR</button>
              <button className="gf-btn gf-btn-primary">Merge</button>
            </div>
          </>}
        </div>
      </div>
    </div>
  );
}

function CheckRow({ name, status, time }) {
  return (
    <div className="gf-check-row">
      <span className={`gf-check-status gf-check-${status}`}>
        {status === 'pass' ? '✓' : status === 'running' ? '●' : '✕'}
      </span>
      <span className="gf-mono">{name}</span>
      <span className="gf-dim gf-mono">{time}</span>
    </div>
  );
}

function ReviewerRow({ name, approved, pending }) {
  return (
    <div className="gf-rev-row">
      <Avatar name={name} size={20} />
      <span>{name}</span>
      <span className={approved ? 'gf-pill gf-pill-clean' : 'gf-pill gf-pill-dirty'}>
        {approved ? '✓ approved' : 'pending'}
      </span>
    </div>
  );
}

// ─── Conflicts ────────────────────────────────────────────────────────
function ConflictView() {
  const [selFile, setSelFile] = uS(CONFLICT_FILES[0].path);
  const [picks, setPicks] = uS(CONFLICT_HUNKS.map(() => null)); // 'ours' | 'theirs' | 'both' | null

  const setPick = (i, v) => setPicks(p => p.map((x, j) => j === i ? v : x));

  return (
    <div className="gf-view-conflict">
      <ContentHeader title="Resolve conflicts"
        subtitle={<span className="gf-mono">merging origin/main into feat/commit-graph</span>}
        right={
          <div className="gf-content-actions">
            <ToolButton icon={I.x} label="Abort merge" />
            <ToolButton icon={I.check} label="Continue merge" primary disabled={picks.includes(null)} />
          </div>
        }
      />

      <div className="gf-conflict-grid">
        <div className="gf-conflict-files">
          <div className="gf-files-h">Files with conflicts</div>
          {CONFLICT_FILES.map(f => (
            <button key={f.path}
                    className={`gf-conflict-file ${selFile === f.path ? 'is-selected' : ''} ${f.resolved ? 'is-resolved' : ''}`}
                    onClick={() => setSelFile(f.path)}>
              <span className="gf-conflict-icon">{f.resolved ? '✓' : '!'}</span>
              <span className="gf-mono">{f.path}</span>
              <span className="gf-dim">{f.conflicts}</span>
            </button>
          ))}
        </div>

        <div className="gf-conflict-hunks">
          <div className="gf-conflict-h">
            <span className="gf-cm-icon">{I.diff}</span>
            <span className="gf-mono">{selFile}</span>
            <span className="gf-dim gf-mono"> · {picks.filter(Boolean).length}/{CONFLICT_HUNKS.length} resolved</span>
          </div>

          {CONFLICT_HUNKS.map((h, i) => (
            <div key={i} className={`gf-cf-hunk ${picks[i] ? 'is-resolved' : ''}`}>
              <div className="gf-cf-hunk-h">
                <span className="gf-mono">Conflict #{i + 1}</span>
                {picks[i] && <span className="gf-pill gf-pill-clean">resolved → {picks[i]}</span>}
              </div>
              <div className="gf-cf-3way">
                <div className={`gf-cf-side gf-cf-ours ${picks[i] === 'ours' ? 'is-picked' : ''}`}
                     onClick={() => setPick(i, 'ours')}>
                  <div className="gf-cf-side-h">
                    <span className="gf-cf-side-tag">ours</span>
                    <span className="gf-mono gf-dim">feat/commit-graph</span>
                  </div>
                  <pre className="gf-cf-code">{h.ours.join('\n')}</pre>
                </div>
                <div className={`gf-cf-side gf-cf-base ${picks[i] === 'both' ? 'is-picked' : ''}`}
                     onClick={() => setPick(i, 'both')}>
                  <div className="gf-cf-side-h">
                    <span className="gf-cf-side-tag">both</span>
                    <span className="gf-mono gf-dim">merge manually</span>
                  </div>
                  <pre className="gf-cf-code">{h.base.join('\n')}</pre>
                </div>
                <div className={`gf-cf-side gf-cf-theirs ${picks[i] === 'theirs' ? 'is-picked' : ''}`}
                     onClick={() => setPick(i, 'theirs')}>
                  <div className="gf-cf-side-h">
                    <span className="gf-cf-side-tag">theirs</span>
                    <span className="gf-mono gf-dim">origin/main</span>
                  </div>
                  <pre className="gf-cf-code">{h.theirs.join('\n')}</pre>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── Blame ────────────────────────────────────────────────────────────
function BlameView() {
  // group consecutive lines by sha
  const groups = [];
  for (const ln of BLAME_LINES) {
    const last = groups[groups.length - 1];
    if (last && last.sha === ln.sha) last.lines.push(ln);
    else groups.push({ sha: ln.sha, author: ln.author, when: ln.when, lines: [ln] });
  }
  return (
    <div className="gf-view-blame">
      <ContentHeader title="Blame" subtitle={<span className="gf-mono">{BLAME_FILE}</span>}
        right={
          <div className="gf-content-actions">
            <ToolButton icon={I.arrowU} label="Prev rev" />
            <ToolButton icon={I.arrowD} label="Next rev" />
          </div>
        }
      />
      <div className="gf-blame-wrap">
        {groups.map((g, i) => (
          <div key={i} className="gf-blame-group" style={{ '--lane-color': lighterFromSha(g.sha) }}>
            <div className="gf-blame-meta">
              <Avatar name={g.author} size={16} />
              <div className="gf-blame-meta-text">
                <span className="gf-blame-author">{g.author}</span>
                <span className="gf-mono gf-dim">{g.sha} · {g.when}</span>
              </div>
            </div>
            <div className="gf-blame-code">
              {g.lines.map(ln => (
                <div key={ln.n} className="gf-blame-line">
                  <span className="gf-blame-n">{ln.n}</span>
                  <span className="gf-blame-s">{ln.s || '\u00A0'}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function lighterFromSha(sha) {
  let h = 0; for (let i = 0; i < sha.length; i++) h = (h * 31 + sha.charCodeAt(i)) | 0;
  const palette = ['#7c5cff', '#56b497', '#ff7e6b', '#dda44b', '#5da4ff', '#c976d9'];
  return palette[Math.abs(h) % palette.length];
}

// ─── Clone repo ───────────────────────────────────────────────────────
function CloneView() {
  return (
    <div className="gf-view-clone">
      <ContentHeader title="Clone a repository" />
      <div className="gf-clone-card">
        <label className="gf-field">
          <span className="gf-field-l">Source URL</span>
          <input className="gf-input" defaultValue="git@github.com:acme/api-core.git" />
        </label>
        <label className="gf-field">
          <span className="gf-field-l">Local path</span>
          <div className="gf-input-row">
            <input className="gf-input" defaultValue="~/code/api-core" />
            <button className="gf-btn">Choose…</button>
          </div>
        </label>
        <label className="gf-field">
          <span className="gf-field-l">Branch</span>
          <input className="gf-input" defaultValue="main" />
        </label>

        <div className="gf-clone-foot">
          <span className="gf-mono gf-dim">SSH key found · ed25519 · m@velez.dev</span>
          <button className="gf-btn gf-btn-primary">Clone</button>
        </div>
      </div>

      <div className="gf-clone-recent">
        <div className="gf-detail-h2">Recent</div>
        {REPOS.map(r => (
          <div key={r.id} className="gf-clone-recent-row">
            <span className="gf-repo-mark" data-org={r.org}>{r.org[0].toUpperCase()}</span>
            <span className="gf-mono">{r.org}/{r.name}</span>
            <span className="gf-dim gf-mono">~/code/{r.name}</span>
            <button className="gf-btn gf-btn-sm">Open</button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Settings ─────────────────────────────────────────────────────────
function SettingsView() {
  return (
    <div className="gf-view-settings">
      <ContentHeader title="Settings" />
      <div className="gf-settings-grid">
        <SettingsSection title="Identity">
          <SettingRow label="Name"  value="Mateo Vélez" />
          <SettingRow label="Email" value="m@velez.dev" />
          <SettingRow label="Signing key" value="ed25519 · 4096" mono />
        </SettingsSection>
        <SettingsSection title="Git">
          <SettingRow label="Default branch" value="main" mono />
          <SettingRow label="Pull strategy"  value="rebase" mono />
          <SettingRow label="Auto-fetch"     value="every 5 min" />
        </SettingsSection>
        <SettingsSection title="Accounts">
          <AccountRow host="github.com"  user="mvelez" />
          <AccountRow host="gitlab.com"  user="m.velez" />
          <AccountRow host="gitea.acme.io" user="mvelez" />
        </SettingsSection>
      </div>
    </div>
  );
}

function SettingsSection({ title, children }) {
  return (
    <div className="gf-settings-section">
      <div className="gf-detail-h2">{title}</div>
      <div className="gf-settings-rows">{children}</div>
    </div>
  );
}

function SettingRow({ label, value, mono }) {
  return (
    <div className="gf-set-row">
      <span className="gf-set-l">{label}</span>
      <span className={mono ? 'gf-mono' : ''}>{value}</span>
      <button className="gf-btn gf-btn-sm">Edit</button>
    </div>
  );
}

function AccountRow({ host, user }) {
  return (
    <div className="gf-set-row">
      <span className="gf-mono">{host}</span>
      <span className="gf-dim gf-mono">@{user}</span>
      <button className="gf-btn gf-btn-sm">Sign out</button>
    </div>
  );
}

// ─── Terminal ─────────────────────────────────────────────────────────
function TerminalView() {
  const lines = [
    { p: '~/code/gitforge', t: 'git status' },
    { o: 'On branch feat/commit-graph' },
    { o: 'Your branch is ahead of origin/feat/commit-graph by 7 commits.' },
    { o: '' },
    { o: 'Changes to be committed:' },
    { o: '  modified:   src/components/CommitGraph.tsx' },
    { o: '  modified:   src/store/commitStore.ts' },
    { o: '  new file:   src/lib/lane-layout.ts' },
    { o: '' },
    { p: '~/code/gitforge', t: 'git log --oneline -5' },
    { o: '8b1d99e fix: scroll restoration on branch switch' },
    { o: '2c7e4b0 Tighten lane spacing for dense histories' },
    { o: 'fe33a02 Merge branch \'main\' into feat/commit-graph' },
    { o: 'd91c8aa Bump react to 18.3.1' },
    { o: '7e2a155 docs: add CONTRIBUTING.md and CODEOWNERS' },
    { p: '~/code/gitforge', t: '' },
  ];
  return (
    <div className="gf-view-terminal">
      <ContentHeader title="Terminal" subtitle={<span className="gf-mono">zsh · ~/code/gitforge</span>} />
      <div className="gf-term">
        {lines.map((ln, i) => (
          ln.t != null
            ? <div key={i} className="gf-term-cmd">
                <span className="gf-term-prompt">{ln.p}</span>
                <span className="gf-term-arrow">›</span>
                <span>{ln.t}{i === lines.length - 1 && <span className="gf-cursor" />}</span>
              </div>
            : <div key={i} className="gf-term-out">{ln.o || '\u00A0'}</div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, {
  StagingView, BranchesView, PullsView, ConflictView,
  BlameView, CloneView, SettingsView, TerminalView,
});

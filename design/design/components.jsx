// components.jsx — UI primitives + reusable components for GitForge

const { useState, useEffect, useRef, useMemo, useCallback } = React;

// ─── Icons (1.5px stroke, 16px box, line-style) ───────────────────────
const Icon = ({ d, size = 16, fill = false, stroke = 'currentColor', sw = 1.5 }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill={fill ? stroke : 'none'}
       stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
    {typeof d === 'string' ? <path d={d} /> : d}
  </svg>
);

const I = {
  graph:    <Icon d="M4 3v4m0 0v6m0-6c0 1.5 1 3 4 3s4 1.5 4 3M12 3v4m0 0v6" />,
  diff:     <Icon d={<><path d="M3 4h6m-6 4h4m-4 4h6"/><path d="M11 6v6m-2-2 2 2 2-2"/></>} />,
  branch:   <Icon d={<><circle cx="4" cy="3.5" r="1.5"/><circle cx="4" cy="12.5" r="1.5"/><circle cx="12" cy="6" r="1.5"/><path d="M4 5v6M4 9c0-1.5 0-3.5 4-3.5"/></>} />,
  pr:       <Icon d={<><circle cx="4" cy="3.5" r="1.5"/><circle cx="4" cy="12.5" r="1.5"/><circle cx="12" cy="12.5" r="1.5"/><path d="M4 5v6M12 4v7"/><path d="M11 3.5h2v0M9.5 2l1.5 1.5L9.5 5"/></>} />,
  conflict: <Icon d={<><path d="M8 1.5 14 13H2L8 1.5z"/><path d="M8 6v3M8 11v.5"/></>} />,
  blame:    <Icon d={<><circle cx="8" cy="8" r="6"/><path d="M8 4v4l2.5 1.5"/></>} />,
  clone:    <Icon d={<><rect x="2.5" y="2.5" width="8" height="8" rx="1"/><path d="M5.5 5.5h6v6h-6"/></>} />,
  settings: <Icon d={<><circle cx="8" cy="8" r="2"/><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.5 1.5M11.5 11.5 13 13M3 13l1.5-1.5M11.5 4.5 13 3"/></>} />,
  terminal: <Icon d={<><rect x="1.5" y="3" width="13" height="10" rx="1"/><path d="m4 6.5 2.5 1.5L4 9.5M8 10h3"/></>} />,
  search:   <Icon d={<><circle cx="7" cy="7" r="4.5"/><path d="m10.5 10.5 3 3"/></>} />,
  plus:     <Icon d="M3 8h10M8 3v10" />,
  minus:    <Icon d="M3 8h10" />,
  dot:      <Icon d={<circle cx="8" cy="8" r="2.5" fill="currentColor"/>} />,
  chevR:    <Icon d="m6 3 5 5-5 5" />,
  chevD:    <Icon d="m3 6 5 5 5-5" />,
  arrowU:   <Icon d="M8 13V3M4 7l4-4 4 4" />,
  arrowD:   <Icon d="M8 3v10M4 9l4 4 4-4" />,
  pull:     <Icon d="M3 4v8M3 4l-2 2M3 4l2 2M11 12V4M11 12l-2-2M11 12l2-2" />,
  push:     <Icon d="M3 12V4M3 4l-2 2M3 4l2 2M11 4v8M11 4l-2 2M11 4l2 2" />,
  fetch:    <Icon d={<><path d="M2.5 8a5.5 5.5 0 0 1 10-3"/><path d="M12.5 2v3h-3"/><path d="M13.5 8a5.5 5.5 0 0 1-10 3"/><path d="M3.5 14v-3h3"/></>} />,
  stash:    <Icon d={<><rect x="2" y="6" width="12" height="3" rx="0.5"/><rect x="2" y="10" width="12" height="3" rx="0.5"/><path d="M3.5 4h9"/></>} />,
  folder:   <Icon d="M2 4.5C2 4 2.4 3.5 3 3.5h3l1.5 1.5H13c.6 0 1 .4 1 1V12c0 .6-.4 1-1 1H3c-.6 0-1-.4-1-1V4.5z" />,
  cmd:      <Icon d={<><rect x="3" y="3" width="10" height="10" rx="2"/><path d="M3 6h10M3 10h10M6 3v10M10 3v10"/></>} sw={1} />,
  check:    <Icon d="m3 8 3.5 3.5L13 5" />,
  x:        <Icon d="M4 4l8 8M12 4l-8 8" />,
  ext:      <Icon d="M6 3H3v10h10v-3M9 3h4v4M7 9 13 3" />,
  diamond:  <Icon d={<path d="M8 2l5 6-5 6-5-6z" fill="currentColor"/>} />,
  square:   <Icon d={<rect x="4" y="4" width="8" height="8" fill="currentColor"/>} />,
  warn:     <Icon d={<><path d="M8 1.5 14 13H2L8 1.5z"/><path d="M8 6v3M8 11v.3"/></>} />,
  more:     <Icon d={<><circle cx="3" cy="8" r="1" fill="currentColor"/><circle cx="8" cy="8" r="1" fill="currentColor"/><circle cx="13" cy="8" r="1" fill="currentColor"/></>} sw={0} />,
  user:     <Icon d={<><circle cx="8" cy="6" r="2.5"/><path d="M3 14c0-2.5 2.2-4 5-4s5 1.5 5 4"/></>} />,
};

// ─── Window chrome (custom, no glass) ─────────────────────────────────
function GFWindow({ children, title = 'GitForge' }) {
  return (
    <div className="gf-window">
      <div className="gf-titlebar">
        <div className="gf-traffic">
          <span className="gf-tl gf-tl-r" />
          <span className="gf-tl gf-tl-y" />
          <span className="gf-tl gf-tl-g" />
        </div>
        <div className="gf-title">{title}</div>
        <div style={{ width: 60 }} />
      </div>
      <div className="gf-window-body">{children}</div>
    </div>
  );
}

// ─── Toolbar pill button ──────────────────────────────────────────────
function ToolButton({ icon, label, badge, onClick, active, disabled, primary }) {
  return (
    <button className={`gf-tbtn ${active ? 'is-active' : ''} ${primary ? 'is-primary' : ''}`}
            onClick={onClick} disabled={disabled}>
      <span className="gf-tbtn-icon">{icon}</span>
      {label && <span>{label}</span>}
      {badge != null && badge > 0 && <span className="gf-tbtn-badge">{badge}</span>}
    </button>
  );
}

// ─── Status pill (ahead/behind/dirty) ─────────────────────────────────
function StatusPill({ ahead = 0, behind = 0, dirty = 0 }) {
  if (!ahead && !behind && !dirty) return <span className="gf-pill gf-pill-clean">clean</span>;
  return (
    <span className="gf-stat-pills">
      {ahead   ? <span className="gf-pill gf-pill-up">↑{ahead}</span> : null}
      {behind  ? <span className="gf-pill gf-pill-dn">↓{behind}</span> : null}
      {dirty   ? <span className="gf-pill gf-pill-dirty">●{dirty}</span> : null}
    </span>
  );
}

// ─── Sidebar (repos + nav) ────────────────────────────────────────────
function Sidebar({ repos, currentRepo, onRepoChange, view, onView, onOpenSearch }) {
  const navItems = [
    { id: 'graph',    label: 'History',       icon: I.graph },
    { id: 'staging',  label: 'Changes',       icon: I.diff,    badge: 3 },
    { id: 'branches', label: 'Branches',      icon: I.branch },
    { id: 'pulls',    label: 'Pull requests', icon: I.pr,      badge: 2 },
    { id: 'conflict', label: 'Conflicts',     icon: I.conflict,badge: 2 },
    { id: 'blame',    label: 'Blame',         icon: I.blame },
    { id: 'terminal', label: 'Terminal',      icon: I.terminal },
  ];
  const bottom = [
    { id: 'clone',    label: 'Clone repo…',   icon: I.clone },
    { id: 'settings', label: 'Settings',      icon: I.settings },
  ];

  return (
    <aside className="gf-sidebar">
      <div className="gf-side-search">
        <button className="gf-search-trigger" onClick={onOpenSearch}>
          <span className="gf-tbtn-icon">{I.search}</span>
          <span>Search</span>
          <kbd>⌘K</kbd>
        </button>
      </div>

      <div className="gf-side-section">
        <div className="gf-side-h">Repositories</div>
        <div className="gf-side-list">
          {repos.map(r => (
            <button key={r.id}
                    className={`gf-repo ${r.id === currentRepo.id ? 'is-current' : ''}`}
                    onClick={() => onRepoChange(r)}>
              <span className="gf-repo-mark" data-org={r.org}>{r.org[0].toUpperCase()}</span>
              <span className="gf-repo-text">
                <span className="gf-repo-name">{r.name}</span>
                <span className="gf-repo-branch">{r.branch}</span>
              </span>
              <StatusPill ahead={r.ahead} behind={r.behind} dirty={r.dirty} />
            </button>
          ))}
        </div>
      </div>

      <div className="gf-side-section">
        <div className="gf-side-h">Workspace</div>
        <nav className="gf-nav">
          {navItems.map(n => (
            <button key={n.id} className={`gf-nav-item ${view === n.id ? 'is-active' : ''}`}
                    onClick={() => onView(n.id)}>
              <span className="gf-nav-icon">{n.icon}</span>
              <span>{n.label}</span>
              {n.badge ? <span className="gf-nav-badge">{n.badge}</span> : null}
            </button>
          ))}
        </nav>
      </div>

      <div className="gf-side-spacer" />

      <div className="gf-side-section">
        <nav className="gf-nav">
          {bottom.map(n => (
            <button key={n.id} className={`gf-nav-item ${view === n.id ? 'is-active' : ''}`}
                    onClick={() => onView(n.id)}>
              <span className="gf-nav-icon">{n.icon}</span>
              <span>{n.label}</span>
            </button>
          ))}
        </nav>
        <div className="gf-user">
          <div className="gf-user-avatar">MV</div>
          <div className="gf-user-name">Mateo Vélez</div>
          <span className="gf-user-status" />
        </div>
      </div>
    </aside>
  );
}

// ─── Top toolbar (per-view) ───────────────────────────────────────────
function ContentHeader({ title, subtitle, right }) {
  return (
    <div className="gf-content-h">
      <div className="gf-content-h-l">
        <h1 className="gf-h1">{title}</h1>
        {subtitle && <span className="gf-content-sub">{subtitle}</span>}
      </div>
      <div className="gf-content-h-r">{right}</div>
    </div>
  );
}

// ─── Branch chip used on commits ──────────────────────────────────────
function BranchChip({ name, remote = false, current = false, tag = false }) {
  return (
    <span className={`gf-branch-chip ${remote ? 'is-remote' : ''} ${current ? 'is-current' : ''} ${tag ? 'is-tag' : ''}`}>
      {tag ? <span className="gf-cm-icon">{I.diamond}</span> : <span className="gf-cm-icon">{I.branch}</span>}
      {name}
    </span>
  );
}

// ─── Avatar ───────────────────────────────────────────────────────────
function Avatar({ name = '?', size = 18 }) {
  const initials = name.split(/\s+/).map(s => s[0]).slice(0, 2).join('').toUpperCase();
  // hash to one of 6 avatar colors
  let h = 0; for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
  const palette = ['#7c5cff', '#ff7e6b', '#56b497', '#dda44b', '#5da4ff', '#c976d9'];
  const bg = palette[Math.abs(h) % palette.length];
  return (
    <span className="gf-avatar" style={{ width: size, height: size, background: bg, fontSize: size * 0.5 }}>
      {initials}
    </span>
  );
}

// ─── Empty state ──────────────────────────────────────────────────────
function EmptyState({ icon, title, subtitle, action }) {
  return (
    <div className="gf-empty">
      <div className="gf-empty-icon">{icon}</div>
      <div className="gf-empty-title">{title}</div>
      {subtitle && <div className="gf-empty-sub">{subtitle}</div>}
      {action}
    </div>
  );
}

Object.assign(window, {
  Icon, I, GFWindow, ToolButton, StatusPill, Sidebar,
  ContentHeader, BranchChip, Avatar, EmptyState,
});

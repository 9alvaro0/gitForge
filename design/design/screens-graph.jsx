// screens-graph.jsx — Commit graph (primary screen) + Diff pane

const LANE_COLORS = [
  '#7c5cff', // primary purple
  '#56b497', // teal
  '#ff7e6b', // coral
  '#dda44b', // amber
  '#5da4ff', // sky
  '#c976d9', // magenta
];

// The graph itself: SVG gutter on the left + commit row.
// Style: option 2 — square nodes, thin lines, monospace metadata.
function CommitGraphSvg({ commits, selected, onSelect, density }) {
  const ROW_H = density === 'compact' ? 26 : density === 'comfy' ? 36 : 30;
  const LANE_W = 14;
  const NODE_S = 8; // square side
  const laneCount = commits.reduce((m, c) => Math.max(m, c.col, ...(c.parents?.map(p => p.col) ?? [])), 0) + 1;
  const gutterW = laneCount * LANE_W + 12;

  return (
    <div className="gf-cgraph" style={{ '--row-h': `${ROW_H}px` }}>
      {commits.map((c, i) => {
        const next = commits[i + 1];
        const isSel = selected === c.sha;
        return (
          <div key={c.sha} className={`gf-cg-row ${isSel ? 'is-sel' : ''} ${c.uncommitted ? 'is-uncommitted' : ''}`}
               onClick={() => onSelect(c.sha)}>
            <div className="gf-cg-gutter" style={{ width: gutterW }}>
              <svg width={gutterW} height={ROW_H} className="gf-cg-svg">
                {/* lines from this commit's node down to its parents (next commits) */}
                {next && drawLanes(c, next, LANE_W, ROW_H, NODE_S)}
                {/* node */}
                <rect
                  x={c.col * LANE_W + 6 - NODE_S / 2}
                  y={(ROW_H - NODE_S) / 2}
                  width={NODE_S}
                  height={NODE_S}
                  fill={c.uncommitted ? '#0d0c10' : LANE_COLORS[c.col % LANE_COLORS.length]}
                  stroke={c.uncommitted ? LANE_COLORS[c.col % LANE_COLORS.length] : 'none'}
                  strokeDasharray={c.uncommitted ? '2 2' : undefined}
                  strokeWidth={c.uncommitted ? 1 : 0}
                />
                {c.merge && (
                  <rect
                    x={c.col * LANE_W + 6 - 2}
                    y={(ROW_H - 4) / 2}
                    width={4} height={4}
                    fill="#0d0c10"
                  />
                )}
              </svg>
            </div>

            <div className="gf-cg-msg">
              {c.uncommitted ? (
                <span className="gf-cg-uncommitted">
                  <span className="gf-cg-pending">●</span>
                  Uncommitted changes
                </span>
              ) : (
                <>
                  <span className="gf-cg-msg-text">{c.msg}</span>
                  {c.branch && <BranchChip name={c.branch} current={i === 0 || c.branch === 'feat/commit-graph'} />}
                  {c.tag && <BranchChip name={c.tag} tag />}
                </>
              )}
            </div>

            <div className="gf-cg-author">
              {!c.uncommitted && (
                <>
                  <Avatar name={c.author} size={16} />
                  <span className="gf-cg-author-name">{c.author}</span>
                </>
              )}
            </div>

            <div className="gf-cg-sha">{c.uncommitted ? '–' : c.sha}</div>
            <div className="gf-cg-when">{c.when}</div>
          </div>
        );
      })}
    </div>
  );
}

// Lines from this row's node to next row's parent positions.
function drawLanes(c, next, LANE_W, ROW_H, NODE_S) {
  const lines = [];
  const fromX = c.col * LANE_W + 6;
  const fromY = ROW_H / 2;
  const toY = ROW_H + ROW_H / 2; // into next row

  // for each parent, draw to next row col (we use parents' col)
  (c.parents ?? []).forEach((p, idx) => {
    const toX = p.col * LANE_W + 6;
    const color = LANE_COLORS[p.col % LANE_COLORS.length];
    if (toX === fromX) {
      lines.push(
        <line key={`v${idx}`} x1={fromX} y1={fromY} x2={toX} y2={ROW_H}
              stroke={color} strokeWidth={1.2} strokeDasharray="2 2" />
      );
    } else {
      // bend
      const mid = ROW_H * 0.85;
      lines.push(
        <path key={`p${idx}`}
              d={`M${fromX} ${fromY} L${fromX} ${ROW_H - 4} Q${fromX} ${ROW_H} ${fromX + Math.sign(toX - fromX) * 4} ${ROW_H} L${toX - Math.sign(toX - fromX) * 4} ${ROW_H} Q${toX} ${ROW_H} ${toX} ${ROW_H + 4} L${toX} ${ROW_H}`}
              stroke={color} strokeWidth={1.2} fill="none" strokeDasharray="2 2" />
      );
    }
  });

  // Also continue any other lanes that don't pass through this commit.
  // (Simplified — we draw a faint vertical for each other lane present in next row.)
  return lines;
}

// ─── Diff pane ─────────────────────────────────────────────────────────
function DiffPane({ file, hunks, viewMode = 'unified', onChangeViewMode }) {
  return (
    <div className="gf-diff">
      <div className="gf-diff-h">
        <span className="gf-diff-file">
          <span className="gf-cm-icon">{I.diff}</span>
          {file}
        </span>
        <div className="gf-diff-h-r">
          <div className="gf-segmented">
            <button className={viewMode === 'unified' ? 'is-active' : ''} onClick={() => onChangeViewMode?.('unified')}>Unified</button>
            <button className={viewMode === 'split' ? 'is-active' : ''} onClick={() => onChangeViewMode?.('split')}>Split</button>
          </div>
          <button className="gf-icon-btn" title="Open in editor">{I.ext}</button>
        </div>
      </div>
      <div className="gf-diff-body">
        {hunks.map((h, i) => (
          <div key={i} className="gf-hunk">
            <div className="gf-hunk-h">{h.header}</div>
            {h.lines.map((ln, j) => (
              <div key={j} className={`gf-dl gf-dl-${ln.t === '+' ? 'add' : ln.t === '-' ? 'del' : 'ctx'}`}>
                <span className="gf-dl-n">{ln.n1 ?? ''}</span>
                <span className="gf-dl-n">{ln.n2 ?? ''}</span>
                <span className="gf-dl-sign">{ln.t}</span>
                <span className="gf-dl-s">{ln.s || '\u00A0'}</span>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Commit detail (right panel) ───────────────────────────────────────
function CommitDetail({ commit, onCheckout }) {
  if (!commit) return null;
  if (commit.uncommitted) {
    return (
      <div className="gf-detail">
        <div className="gf-detail-h">
          <span className="gf-pill gf-pill-dirty">Working tree</span>
        </div>
        <div className="gf-detail-msg">3 changes ready to commit, 4 unstaged.</div>
        <button className="gf-btn gf-btn-primary" style={{ marginTop: 12 }} onClick={() => onCheckout?.('staging')}>
          Open Changes
        </button>
      </div>
    );
  }
  return (
    <div className="gf-detail">
      <div className="gf-detail-sha">
        <span className="gf-cm-icon">{I.diamond}</span>
        <span>{commit.sha}</span>
        <button className="gf-icon-btn" title="Copy SHA">⧉</button>
      </div>
      <div className="gf-detail-msg">{commit.msg}</div>
      <div className="gf-detail-meta">
        <Avatar name={commit.author} size={20} />
        <div className="gf-detail-meta-text">
          <div className="gf-detail-author">{commit.author}</div>
          <div className="gf-detail-email">{commit.email}</div>
        </div>
        <div className="gf-detail-when">{commit.when}</div>
      </div>

      <div className="gf-detail-section">
        <div className="gf-detail-h2">Files changed <span className="gf-detail-stat">3</span></div>
        <div className="gf-files-mini">
          <FileMini status="M" path="src/components/CommitGraph.tsx" added={42} removed={18} active />
          <FileMini status="M" path="src/store/commitStore.ts"        added={11} removed={3} />
          <FileMini status="A" path="src/lib/lane-layout.ts"          added={88} removed={0} />
        </div>
      </div>

      <div className="gf-detail-section">
        <div className="gf-detail-h2">Actions</div>
        <div className="gf-detail-actions">
          <button className="gf-btn">Revert</button>
          <button className="gf-btn">Cherry-pick</button>
          <button className="gf-btn">Reset to here</button>
          <button className="gf-btn">Create branch</button>
        </div>
      </div>
    </div>
  );
}

function FileMini({ status, path, added, removed, active }) {
  const segs = path.split('/');
  return (
    <div className={`gf-fmini ${active ? 'is-active' : ''}`}>
      <span className={`gf-status-tag gf-status-${status}`}>{status}</span>
      <span className="gf-fmini-path">
        <span className="gf-fmini-dir">{segs.slice(0, -1).join('/')}/</span>
        <span className="gf-fmini-name">{segs[segs.length - 1]}</span>
      </span>
      <span className="gf-fmini-stats">
        {added ? <span className="gf-add">+{added}</span> : null}
        {removed ? <span className="gf-del">−{removed}</span> : null}
      </span>
    </div>
  );
}

// ─── Main History view ────────────────────────────────────────────────
function HistoryView({ density, onView }) {
  const [selected, setSelected] = useState(COMMITS[1].sha);
  const [viewMode, setViewMode] = useState('unified');
  const sel = COMMITS.find(c => c.sha === selected);

  return (
    <div className="gf-view-history">
      <ContentHeader
        title="History"
        subtitle={<span className="gf-mono">main · 247 commits</span>}
        right={
          <div className="gf-content-actions">
            <ToolButton icon={I.fetch} label="Fetch" />
            <ToolButton icon={I.pull}  label="Pull" badge={1} />
            <ToolButton icon={I.push}  label="Push" badge={7} primary />
          </div>
        }
      />

      <div className="gf-graph-filters">
        <div className="gf-segmented">
          <button className="is-active">All</button>
          <button>Local</button>
          <button>Remote</button>
          <button>Tags</button>
        </div>
        <div className="gf-graph-filters-r">
          <span className="gf-mono gf-dim">filter:</span>
          <span className="gf-chip-input">author:mvelez</span>
          <button className="gf-icon-btn">+ filter</button>
        </div>
      </div>

      <div className="gf-graph-grid">
        <div className="gf-graph-col">
          <div className="gf-graph-head">
            <span style={{ flex: '0 0 110px' }}>Graph</span>
            <span style={{ flex: 1 }}>Message</span>
            <span style={{ flex: '0 0 130px' }}>Author</span>
            <span style={{ flex: '0 0 80px' }}>SHA</span>
            <span style={{ flex: '0 0 70px' }}>When</span>
          </div>
          <div className="gf-graph-scroll">
            <CommitGraphSvg commits={COMMITS} selected={selected} onSelect={setSelected} density={density} />
          </div>
          <DiffPane file={DIFF_FILE} hunks={DIFF_HUNKS} viewMode={viewMode} onChangeViewMode={setViewMode} />
        </div>

        <div className="gf-detail-col">
          <CommitDetail commit={sel} onCheckout={onView} />
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { HistoryView, CommitGraphSvg, DiffPane, CommitDetail, FileMini, LANE_COLORS });

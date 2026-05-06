// data.jsx — sample repo state shared across the prototype

const REPOS = [
  { id: 'gitforge',   name: 'gitforge',   org: 'mvelez',   branch: 'main',           ahead: 2, behind: 0, dirty: 3 },
  { id: 'web',        name: 'company-web',org: 'acme',     branch: 'feat/checkout',  ahead: 5, behind: 1, dirty: 0 },
  { id: 'api',        name: 'api-core',   org: 'acme',     branch: 'main',           ahead: 0, behind: 0, dirty: 0 },
  { id: 'docs',       name: 'docs',       org: 'acme',     branch: 'main',           ahead: 0, behind: 3, dirty: 0 },
  { id: 'mobile',     name: 'mobile-app', org: 'acme',     branch: 'release/2.4',    ahead: 0, behind: 0, dirty: 12 },
];

const BRANCHES = [
  { name: 'main',                 type: 'local',  current: false, ahead: 2, behind: 0, lastCommit: '2h ago' },
  { name: 'feat/commit-graph',    type: 'local',  current: true,  ahead: 7, behind: 1, lastCommit: 'just now' },
  { name: 'feat/conflict-ui',     type: 'local',  current: false, ahead: 3, behind: 4, lastCommit: '1d ago' },
  { name: 'fix/diff-scroll',      type: 'local',  current: false, ahead: 1, behind: 0, lastCommit: '3d ago' },
  { name: 'origin/main',          type: 'remote', current: false, ahead: 0, behind: 0, lastCommit: '2h ago' },
  { name: 'origin/develop',       type: 'remote', current: false, ahead: 0, behind: 0, lastCommit: '5h ago' },
  { name: 'origin/release/2.4',   type: 'remote', current: false, ahead: 0, behind: 0, lastCommit: '1d ago' },
];

const TAGS = ['v2.3.1', 'v2.3.0', 'v2.2.4', 'v2.2.3'];

// Commit graph — column index defines lane color
const COMMITS = [
  { sha: 'a4f3c12', col: 1, parents: [{col:1}],         msg: 'Wire commit-graph virtualizer to commit store',                  author: 'M. Vélez',   email: 'm@velez.dev',    when: 'just now',  branch: 'feat/commit-graph', uncommitted: true },
  { sha: '8b1d99e', col: 1, parents: [{col:1}],         msg: 'fix: scroll restoration on branch switch',                       author: 'M. Vélez',   email: 'm@velez.dev',    when: '12 min',    },
  { sha: '2c7e4b0', col: 1, parents: [{col:1}],         msg: 'Tighten lane spacing for dense histories',                       author: 'M. Vélez',   email: 'm@velez.dev',    when: '1h',        },
  { sha: 'fe33a02', col: 1, parents: [{col:0},{col:2}], msg: "Merge branch 'main' into feat/commit-graph",                     author: 'M. Vélez',   email: 'm@velez.dev',    when: '3h',        merge: true },
  { sha: 'd91c8aa', col: 0, parents: [{col:0}],         msg: 'Bump react to 18.3.1',                                           author: 'L. Park',    email: 'lp@acme.io',     when: '4h',        branch: 'main', tag: 'v2.3.1' },
  { sha: '7e2a155', col: 0, parents: [{col:0}],         msg: 'docs: add CONTRIBUTING.md and CODEOWNERS',                       author: 'L. Park',    email: 'lp@acme.io',     when: '5h',        },
  { sha: '0aa9b34', col: 2, parents: [{col:0}],         msg: 'feat(diff): word-level intra-line highlight',                    author: 'R. Tanaka',  email: 'rt@acme.io',     when: '6h',        branch: 'feat/conflict-ui' },
  { sha: '6c1f0d8', col: 2, parents: [{col:2}],         msg: 'wip: conflict-resolution gutter',                                author: 'R. Tanaka',  email: 'rt@acme.io',     when: '1d',        },
  { sha: '3d44a91', col: 2, parents: [{col:2},{col:0}], msg: "Merge branch 'main' into feat/conflict-ui",                      author: 'R. Tanaka',  email: 'rt@acme.io',     when: '1d',        merge: true },
  { sha: 'ab02c44', col: 0, parents: [{col:0}],         msg: 'chore(deps): tauri 1.6 → 1.7',                                   author: 'M. Vélez',   email: 'm@velez.dev',    when: '2d',        },
  { sha: '9924781', col: 0, parents: [{col:0}],         msg: 'perf: avoid re-rendering lane gutter on hover',                  author: 'M. Vélez',   email: 'm@velez.dev',    when: '2d',        },
  { sha: '54bb710', col: 3, parents: [{col:0}],         msg: 'fix: diff scroll resets on stage',                               author: 'A. Singh',   email: 'as@acme.io',     when: '3d',        branch: 'fix/diff-scroll' },
  { sha: 'f08d2e1', col: 0, parents: [{col:0}],         msg: 'feat(blame): keyboard nav between revisions',                    author: 'A. Singh',   email: 'as@acme.io',     when: '3d',        },
  { sha: '4471a09', col: 0, parents: [{col:0}],         msg: 'Refactor: split commit store from view models',                  author: 'L. Park',    email: 'lp@acme.io',     when: '4d',        },
  { sha: '1e9c3d2', col: 0, parents: [{col:0}],         msg: 'Initial work on staging area',                                   author: 'M. Vélez',   email: 'm@velez.dev',    when: '5d',        tag: 'v2.3.0' },
  { sha: 'cc4421b', col: 0, parents: [{col:0}],         msg: 'Hello, GitForge.',                                               author: 'M. Vélez',   email: 'm@velez.dev',    when: '6d',        },
];

// Files in working tree for staging view
const WORKING_FILES = [
  { path: 'src/components/CommitGraph.tsx',     status: 'M', staged: true,  added: 42, removed: 18 },
  { path: 'src/store/commitStore.ts',            status: 'M', staged: true,  added: 11, removed: 3  },
  { path: 'src/lib/lane-layout.ts',              status: 'A', staged: true,  added: 88, removed: 0  },
  { path: 'src/components/DiffPane.tsx',         status: 'M', staged: false, added: 6,  removed: 9  },
  { path: 'src/styles/graph.css',                status: 'M', staged: false, added: 2,  removed: 1  },
  { path: 'src/lib/old-graph.ts',                status: 'D', staged: false, added: 0,  removed: 134 },
  { path: 'docs/architecture.md',                status: '?', staged: false, added: 0,  removed: 0   },
];

// Diff sample for the selected commit / file
const DIFF_FILE = 'src/components/CommitGraph.tsx';
const DIFF_HUNKS = [
  { header: '@@ -42,7 +42,12 @@ export function CommitGraph({ commits, selected }: Props) {',
    lines: [
      { t: ' ', n1: 42, n2: 42, s: '  const laneCount = useMemo(() => maxLane(commits) + 1, [commits])' },
      { t: ' ', n1: 43, n2: 43, s: '  const rowH = density === "compact" ? 22 : 28' },
      { t: ' ', n1: 44, n2: 44, s: '' },
      { t: '-', n1: 45, n2: null, s: '  const visible = commits.slice(scrollTop / rowH, (scrollTop + height) / rowH)' },
      { t: '+', n1: null, n2: 45, s: '  const start = Math.max(0, Math.floor(scrollTop / rowH) - 8)' },
      { t: '+', n1: null, n2: 46, s: '  const end   = Math.min(commits.length, Math.ceil((scrollTop + height) / rowH) + 8)' },
      { t: '+', n1: null, n2: 47, s: '  const visible = commits.slice(start, end)' },
      { t: '+', n1: null, n2: 48, s: '' },
      { t: '+', n1: null, n2: 49, s: '  // Anchor first row to its absolute index so transforms align' },
      { t: '+', n1: null, n2: 50, s: '  const offsetY = start * rowH' },
      { t: ' ', n1: 46, n2: 51, s: '' },
      { t: ' ', n1: 47, n2: 52, s: '  return (' },
      { t: ' ', n1: 48, n2: 53, s: '    <div ref={scrollRef} onScroll={onScroll} className="cg-scroller">' },
    ]},
  { header: '@@ -71,4 +76,8 @@ export function CommitGraph({ commits, selected }: Props) {',
    lines: [
      { t: ' ', n1: 71, n2: 76, s: '      </div>' },
      { t: ' ', n1: 72, n2: 77, s: '    </div>' },
      { t: ' ', n1: 73, n2: 78, s: '  )' },
      { t: '+', n1: null, n2: 79, s: '}' },
      { t: '+', n1: null, n2: 80, s: '' },
      { t: '+', n1: null, n2: 81, s: 'function maxLane(commits: Commit[]) {' },
      { t: '+', n1: null, n2: 82, s: '  return commits.reduce((m, c) => Math.max(m, c.col), 0)' },
    ]},
];

// Conflict view
const CONFLICT_FILES = [
  { path: 'src/components/CommitGraph.tsx', resolved: false, conflicts: 2 },
  { path: 'src/store/commitStore.ts',        resolved: true,  conflicts: 1 },
  { path: 'package.json',                    resolved: false, conflicts: 1 },
];

const CONFLICT_HUNKS = [
  {
    ours:   ['  const rowH = density === "compact" ? 22 : 28', '  const offsetY = scrollTop % rowH'],
    base:   ['  const rowH = 24', '  const offsetY = 0'],
    theirs: ['  const rowH = density === "compact" ? 20 : 26', '  const offsetY = scrollTop - (scrollTop % rowH)'],
    resolved: false,
  },
  {
    ours:   ['  return commits.slice(start, end)'],
    base:   ['  return commits'],
    theirs: ['  return memoize(commits.slice(start, end))'],
    resolved: false,
  },
];

// Pull requests
const PULLS = [
  { num: 248, title: 'Wire commit-graph virtualizer to commit store',  author: 'mvelez',   status: 'open',     reviews: 1, checks: 'pass',    branch: 'feat/commit-graph', target: 'main', when: '2h' },
  { num: 247, title: 'feat(diff): word-level intra-line highlight',    author: 'rtanaka',  status: 'open',     reviews: 0, checks: 'running', branch: 'feat/conflict-ui',  target: 'main', when: '6h' },
  { num: 246, title: 'fix: diff scroll resets on stage',               author: 'asingh',   status: 'review',   reviews: 2, checks: 'pass',    branch: 'fix/diff-scroll',   target: 'main', when: '1d' },
  { num: 245, title: 'chore(deps): tauri 1.6 → 1.7',                   author: 'mvelez',   status: 'merged',   reviews: 2, checks: 'pass',    branch: 'chore/tauri',       target: 'main', when: '2d' },
  { num: 244, title: 'docs: add CONTRIBUTING.md and CODEOWNERS',       author: 'lpark',    status: 'merged',   reviews: 1, checks: 'pass',    branch: 'docs/contrib',      target: 'main', when: '5h' },
];

// Blame for a small file
const BLAME_FILE = 'src/lib/lane-layout.ts';
const BLAME_LINES = [
  { sha: '1e9c3d2', author: 'M. Vélez',  when: '5d', n: 1,  s: 'export type Lane = { col: number; color: string }' },
  { sha: '1e9c3d2', author: 'M. Vélez',  when: '5d', n: 2,  s: '' },
  { sha: '1e9c3d2', author: 'M. Vélez',  when: '5d', n: 3,  s: 'export function layoutLanes(commits: Commit[]): Lane[] {' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 4,  s: '  const lanes: Lane[] = []' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 5,  s: '  const seen = new Map<string, number>()' },
  { sha: '2c7e4b0', author: 'M. Vélez',  when: '1h', n: 6,  s: '  let nextCol = 0' },
  { sha: '2c7e4b0', author: 'M. Vélez',  when: '1h', n: 7,  s: '' },
  { sha: '2c7e4b0', author: 'M. Vélez',  when: '1h', n: 8,  s: '  for (const c of commits) {' },
  { sha: '8b1d99e', author: 'M. Vélez',  when: '12m',n: 9,  s: '    const col = seen.get(c.sha) ?? nextCol++' },
  { sha: '8b1d99e', author: 'M. Vélez',  when: '12m',n: 10, s: '    lanes[col] ??= { col, color: laneColor(col) }' },
  { sha: '8b1d99e', author: 'M. Vélez',  when: '12m',n: 11, s: '    for (const p of c.parents) seen.set(p.sha, col)' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 12, s: '  }' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 13, s: '' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 14, s: '  return lanes' },
  { sha: '4471a09', author: 'L. Park',   when: '4d', n: 15, s: '}' },
];

Object.assign(window, {
  REPOS, BRANCHES, TAGS, COMMITS, WORKING_FILES,
  DIFF_FILE, DIFF_HUNKS, CONFLICT_FILES, CONFLICT_HUNKS,
  PULLS, BLAME_FILE, BLAME_LINES,
});

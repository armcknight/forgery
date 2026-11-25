import Foundation

/**
 * Draws a self-contained HTML report.
 *
 * The output has no external references at all: styles and scripts are inline and the charts are
 * drawn with elements rather than a charting library. The file therefore opens correctly with no
 * network, which is the point of writing it to disk.
 *
 * Like `renderTerminalReport`, this is a pure function of the report.
 */
public func renderHTMLReport(_ report: StatusReport, topCount: Int = 5) -> String {
    let rollup = report.rollup(topCount: topCount)

    var body = ""
    body += renderHTMLHeader(report, rollup: rollup)
    body += renderHTMLCharts(rollup)
    body += renderHTMLTopLists(rollup)
    body += renderHTMLRepoTable(report)

    return """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>forgery status</title>
    <style>
    \(htmlStyles)
    </style>
    </head>
    <body>
    <main>
    \(body)
    </main>
    <script>
    \(htmlScript)
    </script>
    </body>
    </html>
    """
}

// MARK: - Sections

private func renderHTMLHeader(_ report: StatusReport, rollup: StatusRollup) -> String {
    var notes = [String]()
    if !report.didFetch {
        notes.append("Remote comparisons are as of your last fetch. Run with <code>--fetch</code> for current data.")
    }
    let failures = report.fetchFailures.count
    if failures > 0 {
        notes.append("\(failures) repo\(failures == 1 ? "" : "s") could not be fetched.")
    }

    let noteMarkup = notes.isEmpty ? "" : "<p class=\"note\">" + notes.joined(separator: "<br>") + "</p>"

    return """
    <header>
      <h1>forgery status</h1>
      <p class="meta">
        <strong>\(rollup.totalScanned)</strong> repos scanned ·
        <strong>\(rollup.needingAttention)</strong> need attention ·
        generated \(escapeHTML(formatTimestamp(report.generatedAt)))
      </p>
      \(noteMarkup)
    </header>
    """
}

private func renderHTMLCharts(_ rollup: StatusRollup) -> String {
    guard rollup.totalScanned > 0 else { return "" }

    var sections = [String]()

    if !rollup.byState.isEmpty {
        let rows = rollup.byState.map { entry in
            barRow(
                label: entry.state.displayName,
                count: entry.count,
                max: rollup.maxStateCount,
                cssClass: "state-\(entry.state.rawValue)"
            )
        }.joined()
        sections.append("<section class=\"chart\"><h2>By state</h2><div class=\"bars\">\(rows)</div></section>")
    }

    if !rollup.byCategory.isEmpty {
        let rows = rollup.byCategory.map { entry in
            barRow(
                label: entry.category.shortName,
                count: entry.count,
                max: rollup.maxCategoryCount,
                cssClass: "category"
            )
        }.joined()
        sections.append("<section class=\"chart\"><h2>Needing attention by type</h2><div class=\"bars\">\(rows)</div></section>")
    }

    return "<div class=\"charts\">" + sections.joined() + "</div>"
}

private func barRow(label: String, count: Int, max maxCount: Int, cssClass: String) -> String {
    let percent = maxCount > 0 ? Int((Double(count) / Double(maxCount)) * 100.0) : 0
    return """
    <div class="bar-row">
      <span class="bar-label">\(escapeHTML(label))</span>
      <span class="bar-track"><span class="bar-fill \(cssClass)" style="width: \(percent)%"></span></span>
      <span class="bar-count">\(count)</span>
    </div>
    """
}

private func renderHTMLTopLists(_ rollup: StatusRollup) -> String {
    var sections = [String]()

    if !rollup.topByAhead.isEmpty {
        let items = rollup.topByAhead.map {
            "<li><span class=\"rank-count\">↑\($0.totalAhead)</span> <span title=\"\(escapeHTML($0.path))\">\(escapeHTML($0.shortLabel))</span></li>"
        }.joined()
        sections.append("<section class=\"top\"><h2>Most unpushed commits</h2><ol>\(items)</ol></section>")
    }

    if !rollup.topByLocalOnly.isEmpty {
        let items = rollup.topByLocalOnly.map {
            "<li><span class=\"rank-count\">\($0.localOnlyBranches.count)</span> <span title=\"\(escapeHTML($0.path))\">\(escapeHTML($0.shortLabel))</span></li>"
        }.joined()
        sections.append("<section class=\"top\"><h2>Most local-only branches</h2><ol>\(items)</ol></section>")
    }

    guard !sections.isEmpty else { return "" }
    return "<div class=\"tops\">" + sections.joined() + "</div>"
}

private func renderHTMLRepoTable(_ report: StatusReport) -> String {
    let repos = report.reportingRepos.sorted { ($0.category.rawValue, $0.shortLabel) < ($1.category.rawValue, $1.shortLabel) }
    guard !repos.isEmpty else {
        return "<section><p class=\"empty\">All repositories are clean and up to date.</p></section>"
    }

    var rows = ""
    for (index, repo) in repos.enumerated() {
        rows += renderHTMLRepoRow(repo, index: index)
    }

    return """
    <section class="repos">
      <h2>Repositories</h2>
      <div class="controls">
        <input type="search" id="filter" placeholder="Filter by name, path or branch" autocomplete="off">
      </div>
      <table id="repo-table">
        <thead>
          <tr>
            <th data-sort="tag">Status</th>
            <th data-sort="name">Repository</th>
            <th data-sort="type">Type</th>
            <th data-sort="ahead">Ahead</th>
            <th data-sort="behind">Behind</th>
            <th data-sort="branches">Branches</th>
          </tr>
        </thead>
        <tbody>
    \(rows)
        </tbody>
      </table>
    </section>
    """
}

private func renderHTMLRepoRow(_ repo: RepoSummary, index: Int) -> String {
    let flagMarkup = repo.description.map { "<span class=\"flag flag-\($0)\">\($0)</span>" }.joined()
    let searchText = ([repo.path, repo.shortLabel] + repo.branches.map { $0.name }).joined(separator: " ").lowercased()

    var detail = ""
    if !repo.branches.isEmpty {
        let branchRows = repo.branches.map { branch -> String in
            let name = branch.isCurrent ? "<strong>\(escapeHTML(branch.name))</strong>" : escapeHTML(branch.name)
            return """
            <tr>
              <td>\(name)\(branch.isCheckedOutElsewhere ? " <span class=\"tagline\">worktree</span>" : "")</td>
              <td>\(branch.upstream.map { escapeHTML($0) } ?? "<span class=\"tagline\">no upstream</span>")\(branch.upstreamGone ? " <span class=\"tagline warn\">gone</span>" : "")</td>
              <td class="num">\(branch.ahead > 0 ? "↑\(branch.ahead)" : "")</td>
              <td class="num">\(branch.behind > 0 ? "↓\(branch.behind)" : "")</td>
            </tr>
            """
        }.joined()
        detail += """
        <table class="branches">
          <thead><tr><th>Branch</th><th>Upstream</th><th>Ahead</th><th>Behind</th></tr></thead>
          <tbody>\(branchRows)</tbody>
        </table>
        """
    }
    if let detachedAt = repo.detachedAt {
        detail += "<p class=\"tagline\">HEAD is detached at \(escapeHTML(detachedAt))</p>"
    }
    if repo.workingTree.hasStashes {
        detail += "<p class=\"tagline\">\(repo.workingTree.stashes) stashed change\(repo.workingTree.stashes == 1 ? "" : "s")</p>"
    }
    if let diffstat = repo.diffstat, !diffstat.isEmpty {
        detail += "<pre>\(escapeHTML(diffstat))</pre>"
    }

    return """
        <tr class="repo-row" data-index="\(index)" data-search="\(escapeHTML(searchText))" data-tag="\(escapeHTML(repo.description))" data-name="\(escapeHTML(repo.shortLabel))" data-type="\(escapeHTML(repo.category.shortName))" data-ahead="\(repo.totalAhead)" data-behind="\(repo.totalBehind)" data-branches="\(repo.branches.count)">
          <td class="flags">\(flagMarkup)</td>
          <td class="name" title="\(escapeHTML(repo.path))">\(escapeHTML(repo.shortLabel))</td>
          <td>\(escapeHTML(repo.category.shortName))</td>
          <td class="num">\(repo.totalAhead > 0 ? String(repo.totalAhead) : "")</td>
          <td class="num">\(repo.totalBehind > 0 ? String(repo.totalBehind) : "")</td>
          <td class="num">\(repo.branches.count)</td>
        </tr>
        <tr class="detail-row" data-detail="\(index)"><td colspan="6">\(detail)</td></tr>
    """
}

// MARK: - Assets

private let htmlStyles = """
:root {
  --bg: #fbfbfa; --panel: #ffffff; --fg: #1c1c1a; --muted: #6b6b66;
  --line: #e2e2dd; --accent: #7a5cff; --warn: #b4541f; --ok: #2c7a4b;
  --bar: #7a5cff; --bar-clean: #b8b8b2;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16161a; --panel: #1e1e23; --fg: #ececea; --muted: #9a9a94;
    --line: #303038; --accent: #a08cff; --warn: #e08a55; --ok: #6cc08a;
    --bar: #a08cff; --bar-clean: #4a4a52;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.25rem; background: var(--bg); color: var(--fg);
  font: 15px/1.5 ui-sans-serif, -apple-system, "Helvetica Neue", sans-serif;
}
main { max-width: 68rem; margin: 0 auto; }
h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
h2 { font-size: .95rem; margin: 0 0 .75rem; color: var(--muted); font-weight: 600;
     text-transform: uppercase; letter-spacing: .04em; }
header { margin-bottom: 2rem; }
.meta { margin: 0; color: var(--muted); }
.note { margin: .75rem 0 0; padding: .6rem .8rem; border-left: 3px solid var(--warn);
        background: var(--panel); color: var(--muted); border-radius: 0 6px 6px 0; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
.charts, .tops { display: grid; grid-template-columns: repeat(auto-fit, minmax(19rem, 1fr));
                 gap: 1.25rem; margin-bottom: 1.75rem; }
section.chart, section.top, section.repos {
  background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 1.1rem;
}
.bars { display: flex; flex-direction: column; gap: .4rem; }
.bar-row { display: grid; grid-template-columns: 8.5rem 1fr 2.5rem; align-items: center; gap: .6rem; }
.bar-label { color: var(--muted); font-size: .87rem; }
.bar-track { background: color-mix(in srgb, var(--line) 60%, transparent);
             border-radius: 4px; height: .7rem; overflow: hidden; }
.bar-fill { display: block; height: 100%; background: var(--bar); border-radius: 4px; }
.bar-fill.state-clean { background: var(--bar-clean); }
.bar-fill.state-diverged, .bar-fill.state-upstreamGone { background: var(--warn); }
.bar-count { text-align: right; font-variant-numeric: tabular-nums; font-size: .87rem; }
.tops ol { margin: 0; padding-left: 1.2rem; }
.tops li { margin-bottom: .3rem; }
.rank-count { font-variant-numeric: tabular-nums; color: var(--muted); margin-right: .4rem; }
.controls { margin-bottom: .9rem; }
#filter { width: 100%; padding: .55rem .7rem; border: 1px solid var(--line); border-radius: 7px;
          background: var(--bg); color: var(--fg); font: inherit; }
table { width: 100%; border-collapse: collapse; }
.repos { overflow-x: auto; }
th { text-align: left; font-size: .78rem; text-transform: uppercase; letter-spacing: .04em;
     color: var(--muted); padding: .4rem .5rem; border-bottom: 1px solid var(--line);
     cursor: pointer; user-select: none; white-space: nowrap; }
td { padding: .45rem .5rem; border-bottom: 1px solid var(--line); vertical-align: top; }
.repo-row { cursor: pointer; }
.repo-row:hover { background: color-mix(in srgb, var(--accent) 8%, transparent); }
.num { text-align: right; font-variant-numeric: tabular-nums; }
.name { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88rem; }
.flags { white-space: nowrap; }
.flag { display: inline-block; width: 1.25rem; text-align: center; margin-right: 1px;
        border-radius: 4px; font-size: .75rem; font-weight: 700;
        background: color-mix(in srgb, var(--accent) 18%, transparent); color: var(--fg); }
.flag-D, .flag-G { background: color-mix(in srgb, var(--warn) 28%, transparent); }
.detail-row { display: none; }
.detail-row.open { display: table-row; }
.detail-row > td { background: color-mix(in srgb, var(--line) 22%, transparent); }
table.branches { margin: .3rem 0; font-size: .88rem; }
table.branches th { border-bottom: none; padding-top: 0; cursor: default; }
.tagline { color: var(--muted); font-size: .82rem; }
.tagline.warn { color: var(--warn); }
pre { margin: .5rem 0 0; padding: .6rem; overflow-x: auto; border-radius: 6px;
      background: color-mix(in srgb, var(--line) 30%, transparent);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .82rem; }
.empty { color: var(--muted); margin: 0; }
"""

private let htmlScript = """
(function () {
  var table = document.getElementById('repo-table');
  if (!table) return;
  var body = table.tBodies[0];

  body.addEventListener('click', function (event) {
    var row = event.target.closest('.repo-row');
    if (!row) return;
    var detail = body.querySelector('.detail-row[data-detail="' + row.dataset.index + '"]');
    if (detail) detail.classList.toggle('open');
  });

  var filter = document.getElementById('filter');
  if (filter) {
    filter.addEventListener('input', function () {
      var term = filter.value.trim().toLowerCase();
      Array.prototype.forEach.call(body.querySelectorAll('.repo-row'), function (row) {
        var match = !term || row.dataset.search.indexOf(term) !== -1;
        row.style.display = match ? '' : 'none';
        var detail = body.querySelector('.detail-row[data-detail="' + row.dataset.index + '"]');
        if (detail && !match) { detail.classList.remove('open'); }
      });
    });
  }

  var ascending = {};
  Array.prototype.forEach.call(table.tHead.rows[0].cells, function (cell) {
    cell.addEventListener('click', function () {
      var key = cell.dataset.sort;
      if (!key) return;
      var numeric = key === 'ahead' || key === 'behind' || key === 'branches';
      ascending[key] = !ascending[key];
      var direction = ascending[key] ? 1 : -1;

      var pairs = Array.prototype.map.call(body.querySelectorAll('.repo-row'), function (row) {
        return [row, body.querySelector('.detail-row[data-detail="' + row.dataset.index + '"]')];
      });

      pairs.sort(function (a, b) {
        var left = a[0].dataset[key], right = b[0].dataset[key];
        if (numeric) return (Number(left) - Number(right)) * direction;
        return left.localeCompare(right) * direction;
      });

      pairs.forEach(function (pair) {
        body.appendChild(pair[0]);
        if (pair[1]) body.appendChild(pair[1]);
      });
    });
  });
})();
"""

// MARK: - Helpers

/// Escapes the five characters that would otherwise be read as markup.
func escapeHTML(_ string: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(string.count)
    for character in string {
        switch character {
        case "&": escaped += "&amp;"
        case "<": escaped += "&lt;"
        case ">": escaped += "&gt;"
        case "\"": escaped += "&quot;"
        case "'": escaped += "&#39;"
        default: escaped.append(character)
        }
    }
    return escaped
}

private func formatTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
    return formatter.string(from: date)
}

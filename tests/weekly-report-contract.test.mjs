import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('weekly report is native, semantic, and exported with ImageRenderer', async () => {
  const [source, panel] = await Promise.all([
    readFile(new URL('../Sources/FlickyAshtray/WeeklyReport.swift', import.meta.url), 'utf8'),
    readFile(new URL('../Sources/FlickyAshtray/ControlPanelView.swift', import.meta.url), 'utf8'),
  ]);

  assert.match(source, /ImageRenderer/);
  assert.match(source, /NSSavePanel/);
  assert.match(source, /allowedContentTypes\s*=\s*\[\.png\]/);
  assert.match(source, /VisualAssets\.ashtray/);
  assert.match(source, /Image\(systemName:/);
  assert.match(source, /enum WeeklyReportExportTheme/);
  assert.match(source, /case light/);
  assert.match(source, /case dark/);
  assert.match(source, /NSColor\(\s*srgbRed:/);
  assert.match(source, /WeeklyReportCard\(report: report, theme: theme\)/);
  assert.doesNotMatch(source, /\.(windowBackgroundColor|controlBackgroundColor|separatorColor)/);
  assert.doesNotMatch(source, /Color\.accentColor/);
  assert.doesNotMatch(source, /WebView|WKWebView|preferredColorScheme/);
  assert.doesNotMatch(source, /Color\.(white|black)\b/);
  assert.match(panel, /生成周报…/);
  assert.match(panel, /WeeklyReportExporter\.export/);
});

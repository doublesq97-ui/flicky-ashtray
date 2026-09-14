import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('shipping shell is native AppKit with real close and minimize controls', async () => {
  const [packageFile, windowController] = await Promise.all([
    read('../Package.swift'),
    read('../Sources/FlickyAshtray/ControlPanelWindowController.swift'),
  ]);

  assert.match(packageFile, /\.executable\(name: "FlickyAshtray"/);
  assert.match(windowController, /\.titled/);
  assert.match(windowController, /\.closable/);
  assert.match(windowController, /\.miniaturizable/);
  assert.match(windowController, /window\.center\(\)[\s\S]*setFrameAutosaveName/);
  assert.doesNotMatch(windowController, /zoomButton\).*isHidden\s*=\s*false/);
});

test('native shell uses system material and never ships a WebView card frame', async () => {
  const [windowController, buildScript] = await Promise.all([
    read('../Sources/FlickyAshtray/PetWindowController.swift'),
    read('../scripts/build-app.sh'),
  ]);

  assert.match(windowController, /isMovableByWindowBackground\s*=\s*false/);
  assert.match(windowController, /performDrag\(with:\s*event\)/);
  assert.match(buildScript, /swift build/);
  assert.doesNotMatch(buildScript, /tauri build/);
});

test('the app remains discoverable from the Dock and Dock reopen shows the control panel', async () => {
  const appDelegate = await read('../Sources/FlickyAshtray/AppDelegate.swift');

  assert.match(appDelegate, /setActivationPolicy\(\.regular\)/);
  assert.match(appDelegate, /applicationShouldHandleReopen[\s\S]*showControlPanel\(\)/);
  assert.match(appDelegate, /onPersistenceError[\s\S]*showControlPanel\(\)/);
  assert.match(appDelegate, /persistenceErrorMessage\s*!=\s*nil[\s\S]*controlPanelWindowController\.show\(\)/);
});

test('the regular app exposes familiar macOS menus without stealing document shortcuts', async () => {
  const appDelegate = await read('../Sources/FlickyAshtray/AppDelegate.swift');

  for (const title of [
    '设置…',
    '隐藏 Flicky Ashtray',
    '隐藏其他',
    '关闭窗口',
    '撤销',
    '重做',
    '剪切',
    '拷贝',
    '粘贴',
    '全选',
    '最小化',
    '缩放',
    '全部移到前面',
  ]) {
    assert.match(appDelegate, new RegExp(title));
  }
  assert.match(appDelegate, /item\("设置…",\s*#selector\(showControlPanelAction\),\s*","\)/);
  assert.match(appDelegate, /item\("记一根",\s*#selector\(addRecord\),\s*""\)/);
  assert.match(appDelegate, /item\("撤销今日上一根",\s*#selector\(undoRecord\),\s*""\)/);
});

test('destructive reset is never the default Return action', async () => {
  const resetSheet = await read('../Sources/FlickyAshtray/ResetHistorySheet.swift');

  assert.match(resetSheet, /Button\("确认清空",\s*role:\s*\.destructive\)/);
  assert.doesNotMatch(resetSheet, /确认清空[\s\S]{0,180}keyboardShortcut\(\.defaultAction\)/);
});

test('control panel sections are native, collapsible and remember the user\'s choices', async () => {
  const [panel, windowController] = await Promise.all([
    read('../Sources/FlickyAshtray/ControlPanelView.swift'),
    read('../Sources/FlickyAshtray/ControlPanelWindowController.swift'),
  ]);

  assert.match(panel, /DisclosureGroup/);
  assert.match(panel, /GroupBox/);
  assert.equal((panel.match(/@AppStorage\("controlPanel\.section\./g) ?? []).length, 6);
  assert.match(panel, /WeeklyCadence\.allCases/);
  assert.match(panel, /Slider\(value:\s*\$petScale,\s*in:\s*0\.6\.\.\.1\.0/);
  assert.match(panel, /calendar\.badge\.checkmark/);
  assert.match(panel, /trendMaximum/);
  assert.match(panel, /trendBarHeight\(for:/);
  assert.match(panel, /accessibilityLabel\([\s\S]*day\.count/);
  assert.match(panel, /persistenceErrorMessage/);
  assert.match(panel, /exclamationmark\.triangle\.fill/);
  assert.match(windowController, /minSize\s*=\s*NSSize\(width:\s*460,/);
});

test('borderless pet drag stays native while constraining every frame to a visible screen', async () => {
  const [controller, layout] = await Promise.all([
    read('../Sources/FlickyAshtray/PetWindowController.swift'),
    read('../Sources/FlickyAshtray/PetLayout.swift'),
  ]);

  assert.match(controller, /performDrag\(with:\s*event\)/);
  assert.match(controller, /override func constrainFrameRect/);
  assert.match(layout, /dragIntentThreshold:\s*CGFloat\s*=\s*6/);
  assert.match(controller, /PetLayout\.isDragIntent/);
  assert.match(controller, /PetLayout\.clampedOrigin/);
  assert.match(controller, /setFrameOrigin\(originBefore\)/);
});

test('packaged app and DMG carry the code and AI-asset license notices', async () => {
  const build = await read('../scripts/build-app.sh');

  assert.match(build, /RESOURCES_DIR\/LICENSE\.txt/);
  assert.match(build, /RESOURCES_DIR\/ASSET-LICENSE\.md/);
  assert.match(build, /Licenses\/MIT\.txt/);
  assert.match(build, /Licenses\/AI-ASSETS-CC0\.md/);
});

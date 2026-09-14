import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('Windows release is a native WPF tray app rather than a web wrapper', async () => {
  const [project, controller] = await Promise.all([
    read('../Windows/FlickyAshtray.Windows/FlickyAshtray.Windows.csproj'),
    read('../Windows/FlickyAshtray.Windows/AppController.cs'),
  ]);

  assert.match(project, /<UseWPF>true<\/UseWPF>/);
  assert.match(project, /<UseWindowsForms>true<\/UseWindowsForms>/);
  assert.match(controller, /NotifyIcon/);
  assert.doesNotMatch(project, /WebView|Electron|Tauri/i);
});

test('Windows pet preserves both native styles, hover status and click debounce', async () => {
  const [view, code, status] = await Promise.all([
    read('../Windows/FlickyAshtray.Windows/PetWindow.xaml'),
    read('../Windows/FlickyAshtray.Windows/PetWindow.xaml.cs'),
    read('../Windows/FlickyAshtray.Windows/StatusWindow.xaml.cs'),
  ]);

  assert.match(view, /AshtraySurface/);
  assert.match(view, /NoteSurface/);
  assert.match(view, /ashtray\.png/);
  assert.match(view, /cigarette\.png/);
  assert.match(code, /SystemInformation\.DoubleClickTime/);
  assert.match(code, /DragMove\(\)/);
  assert.match(status, /PetHoverChanged/);
  assert.match(status, /pinned/);
});

test('Windows control panel carries the complete user loop', async () => {
  const panel = await read('../Windows/FlickyAshtray.Windows/ControlPanelWindow.xaml');

  for (const label of ['今日状态', '本周目标', '最近 7 天', '今日记录', '设置', '重新开始', '生成周报']) {
    assert.match(panel, new RegExp(label));
  }
});

test('Windows storage keeps v8 compatibility and protects corrupt or future data', async () => {
  const repository = await read('../Windows/FlickyAshtray.Core/StoreRepository.cs');

  assert.match(repository, /CurrentVersion/);
  assert.match(repository, /StoreLoadStatus\.Corrupt/);
  assert.match(repository, /UnsupportedFutureVersion/);
  assert.match(repository, /BackupPath/);
  assert.match(repository, /pre-migration\.bak/);
  assert.match(repository, /WriteAtomic/);
});

test('Windows preview is self-contained and ships both noncommercial notices', async () => {
  const [project, build] = await Promise.all([
    read('../Windows/FlickyAshtray.Windows/FlickyAshtray.Windows.csproj'),
    read('../scripts/build-windows.sh'),
  ]);

  assert.match(project, /Licenses\/LICENSE\.txt/);
  assert.match(project, /Licenses\/ASSET-LICENSE\.md/);
  assert.match(build, /--self-contained true/);
  assert.match(build, /PublishSingleFile=true/);
  assert.match(build, /IncludeNativeLibrariesForSelfExtract=true/);
});

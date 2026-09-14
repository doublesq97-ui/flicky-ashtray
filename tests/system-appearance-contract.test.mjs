import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('native UI follows macOS appearance and semantic colors', async () => {
  const [panel, pet, statusPanel, info] = await Promise.all([
    readFile(new URL('../Sources/FlickyAshtray/ControlPanelView.swift', import.meta.url), 'utf8'),
    readFile(new URL('../Sources/FlickyAshtray/PetSurfaceView.swift', import.meta.url), 'utf8'),
    readFile(new URL('../Sources/FlickyAshtray/StatusPanelController.swift', import.meta.url), 'utf8'),
    readFile(new URL('../Packaging/Info.plist', import.meta.url), 'utf8'),
  ]);

  const source = `${panel}\n${pet}`;
  assert.doesNotMatch(source, /preferredColorScheme/);
  assert.doesNotMatch(source, /Color\.(white|black)\b/);
  assert.doesNotMatch(info, /NSRequiresAquaSystemAppearance/);
  assert.match(source, /Color\.accentColor|foregroundStyle\(\.tint\)/);
  assert.match(source, /foregroundStyle\(\.secondary\)/);
  assert.match(statusPanel, /material\s*=\s*\.popover/);
  assert.doesNotMatch(statusPanel, /material\s*=\s*\.hudWindow/);
});

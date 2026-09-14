import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('undo is limited by the model in both control panel and menu bar', async () => {
  const [panel, appDelegate] = await Promise.all([
    read('../Sources/FlickyAshtray/ControlPanelView.swift'),
    read('../Sources/FlickyAshtray/AppDelegate.swift'),
  ]);

  assert.match(panel, /disabled\(!model\.canUndoToday\)/);
  assert.match(appDelegate, /undoMenuItem\?\.isEnabled\s*=\s*model\.canUndoToday/);
});

test('history reset requires a reason and a second destructive confirmation', async () => {
  const sheet = await read('../Sources/FlickyAshtray/ResetHistorySheet.swift');

  assert.match(sheet, /trimmedReason\.count\s*>=\s*4/);
  assert.match(sheet, /认真对待自己/);
  assert.match(sheet, /isFinalConfirmation\s*=\s*true/);
  assert.match(sheet, /我确认要清空这些记录/);
  assert.match(sheet, /Button\("确认清空", role:\s*\.destructive\)/);
  assert.match(sheet, /disabled\(!confirmsFinalReset\)/);
});

test('unsaved counting settings cannot silently change a weekly challenge promise', async () => {
  const [panel, model] = await Promise.all([
    read('../Sources/FlickyAshtray/ControlPanelView.swift'),
    read('../Sources/FlickyAshtray/AppModel.swift'),
  ]);

  assert.match(panel, /hasUnsavedCountingSettings/);
  assert.match(panel, /先保存每日上限和计数日起点/);
  assert.match(model, /dayStartHour:\s*store\.settings\.dayStartHour/);
  assert.match(model, /periodStart:\s*periodStart/);
});

test('menu state is refreshed by the clock when the counting day rolls over', async () => {
  const model = await read('../Sources/FlickyAshtray/AppModel.swift');
  assert.match(model, /Timer\.scheduledTimer[\s\S]*onStateChange\?\(\)/);
});

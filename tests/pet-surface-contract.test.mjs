import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('the always-present surface is a small transparent borderless pet window', async () => {
  const [controller, surface] = await Promise.all([
    read('../Sources/FlickyAshtray/PetWindowController.swift'),
    read('../Sources/FlickyAshtray/PetSurfaceView.swift'),
  ]);
  assert.match(controller, /styleMask:\s*\[\.borderless,\s*\.nonactivatingPanel\]/);
  assert.match(controller, /isOpaque\s*=\s*false/);
  assert.match(controller, /backgroundColor\s*=\s*\.clear/);
  assert.match(controller, /isMovableByWindowBackground\s*=\s*false/);
  assert.match(controller, /func finishNativeDrag\(\)/);
  assert.match(controller, /performDrag\(with:\s*event\)/);
  assert.match(controller, /PetLayout\.dragHitRect\(for:\s*petStyle\)/);
  assert.match(controller, /PetLayout\.containsPrimaryAction\(point,\s*style:\s*petStyle\)/);
  assert.doesNotMatch(surface, /DragGesture/);
});

test('settings and history live in a separate on-demand native control panel', async () => {
  const controller = await read('../Sources/FlickyAshtray/ControlPanelWindowController.swift');
  assert.match(controller, /\.titled/);
  assert.match(controller, /\.closable/);
  assert.match(controller, /\.miniaturizable/);
  assert.match(controller, /window\.level\s*=\s*\.normal/);
});

test('dragging preserves pin state and delayed hover hide cannot win a pin race', async () => {
  const [appDelegate, statusController, surface] = await Promise.all([
    read('../Sources/FlickyAshtray/AppDelegate.swift'),
    read('../Sources/FlickyAshtray/StatusPanelController.swift'),
    read('../Sources/FlickyAshtray/PetSurfaceView.swift'),
  ]);

  assert.match(appDelegate, /onDragBegan[\s\S]*hideForDrag\(\)/);
  assert.match(statusController, /func hideForDrag\(\)[\s\S]*orderOut/);
  assert.match(statusController, /func togglePinned[\s\S]*cancelScheduledHide\(\)[\s\S]*pinned\.toggle\(\)/);
  assert.match(statusController, /if pinned \{[\s\S]*show\(relativeTo: petFrame\)[\s\S]*\} else \{[\s\S]*window\?\.orderOut\(nil\)/);
  assert.match(statusController, /guard let self, !self\.pinned else \{ return \}/);
  assert.match(surface, /Button\(action:\s*onTogglePin\)/);
  assert.match(surface, /取消固定今日状态/);
  assert.doesNotMatch(appDelegate, /onAshtrayClick\s*=/);
  const petSurfaceOnly = surface.split('struct StatusCardView')[0];
  assert.equal((petSurfaceOnly.match(/\.onHover\(perform:\s*onHover\)/g) ?? []).length, 1);
});

test('pet scaling keeps native window, artwork and hit testing on one geometry', async () => {
  const [controller, layout, surface, model] = await Promise.all([
    read('../Sources/FlickyAshtray/PetWindowController.swift'),
    read('../Sources/FlickyAshtray/PetLayout.swift'),
    read('../Sources/FlickyAshtray/PetSurfaceView.swift'),
    read('../Sources/FlickyAshtray/AppModel.swift'),
  ]);

  assert.match(controller, /func updateScale\(_ proposedScale: Double\)/);
  assert.match(controller, /basePoint\([\s\S]*interactionScale/);
  assert.match(layout, /minimumScale:\s*CGFloat\s*=\s*0\.6/);
  assert.match(surface, /scaleEffect\(PetLayout\.normalizedScale\(scale\)/);
  assert.match(model, /onPetScaleChange/);
});

test('ashtray and desktop note are one persisted pet with style-aware geometry', async () => {
  const [panel, controller, layout, surface, model] = await Promise.all([
    read('../Sources/FlickyAshtray/ControlPanelView.swift'),
    read('../Sources/FlickyAshtray/PetWindowController.swift'),
    read('../Sources/FlickyAshtray/PetLayout.swift'),
    read('../Sources/FlickyAshtray/PetSurfaceView.swift'),
    read('../Sources/FlickyAshtray/AppModel.swift'),
  ]);

  assert.match(panel, /Picker\("外观",\s*selection:\s*\$petStyle\)/);
  assert.match(panel, /model\.updateSettings\([\s\S]*petStyle:\s*petStyle/);
  assert.match(surface, /case \.ashtray:[\s\S]*ashtraySurface/);
  assert.match(surface, /case \.note:[\s\S]*noteSurface/);
  assert.match(surface, /struct IgniterButton/);
  assert.match(surface, /acceptsRecordAction\(\)[\s\S]*guard !isIgniterBusy else \{ return \}[\s\S]*isIgniterBusy = true[\s\S]*model\.addRecord\(\)/);
  assert.match(surface, /private func recordOne\(\)[\s\S]*acceptsRecordAction\(\)[\s\S]*guard !isTappingAsh/);
  assert.match(surface, /private func recordFromNote\(\)[\s\S]*acceptsRecordAction\(\)[\s\S]*guard !isIgniterBusy/);
  assert.match(surface, /NSEvent\.doubleClickInterval/);
  assert.match(surface, /ignitionTask\?\.cancel\(\)/);
  assert.match(surface, /fadeNanoseconds[\s\S]*isIgniterBusy = false/);
  assert.match(surface, /onChange\(of: petStyle\)[\s\S]*cancelIgnitionFeedback\(\)/);
  assert.match(surface, /private func cancelIgnitionFeedback\(\)[\s\S]*isIgniterLit = false[\s\S]*isIgniterBusy = false/);
  assert.match(surface, /accessibilityReduceMotion/);
  assert.match(controller, /func updateStyle\(_ style: PetStyle\)/);
  assert.match(layout, /func scaledSurfaceSize\([\s\S]*style:\s*PetStyle/);
  assert.match(model, /onPetStyleChange/);
});

test('control panel footer identifies the author and links to GitHub', async () => {
  const panel = await read('../Sources/FlickyAshtray/ControlPanelView.swift');

  assert.match(panel, /Text\("@Sukiea1008"\)/);
  assert.match(panel, /Link\("github\.com\/Sukiea1008"/);
  assert.match(panel, /https:\/\/github\.com\/Sukiea1008/);
});

test('status card cannot open settings and each excess stage has dedicated artwork', async () => {
  const [surface, assets, build] = await Promise.all([
    read('../Sources/FlickyAshtray/PetSurfaceView.swift'),
    read('../Sources/FlickyAshtray/VisualAssets.swift'),
    read('../scripts/build-app.sh'),
  ]);

  const statusCard = surface.split('struct StatusCardView')[1] ?? '';
  assert.doesNotMatch(statusCard, /查看记录与设置|onOpen/);
  assert.match(surface, /case \.overLimit:[\s\S]*VisualAssets\.overLimit/);
  assert.match(surface, /case \.filthy:[\s\S]*VisualAssets\.filthy/);
  assert.match(assets, /ash-over/);
  assert.match(assets, /ash-filthy/);
  assert.match(build, /assets\/ash-over\.png/);
  assert.match(build, /assets\/ash-filthy\.png/);
});

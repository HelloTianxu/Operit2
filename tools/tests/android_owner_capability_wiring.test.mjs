import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const android = 'apps/flutter/app/android/app/src/main/kotlin/app/operit/';

test('Android file presentation is routed to the owner and retains URI read grants', () => {
  const runtime = source('apps/flutter/native/operit-flutter-bridge/src/platform_runtime/android.rs');
  const channel = source(android + 'OwnerSystemCapabilityChannel.kt');
  const documents = source(android + 'AndroidDocumentFileSystem.kt');
  const opener = source(android + 'AndroidFileOpener.kt');
  assert.match(runtime, /AndroidFileSystemHost::withPresentation/);
  assert.match(runtime, /"android_file_presentation"/);
  assert.match(channel, /"android_file_presentation"[\s\S]*fileSystemResourceOperation/);
  assert.match(documents, /"openFile", "shareFile"/);
  assert.match(documents, /target\.input\(\)\.use/);
  assert.match(opener, /Intent\.ACTION_SEND/);
  assert.match(opener, /Intent\.EXTRA_STREAM/);
  assert.match(opener, /FLAG_GRANT_READ_URI_PERMISSION/);
});

test('privileged Android runtime forwards local inference to its owner', () => {
  const runtime = source('apps/flutter/native/operit-flutter-bridge/src/platform_runtime/android.rs');
  const channel = source(android + 'OwnerSystemCapabilityChannel.kt');
  // The owner speech bridge is nested inside the native inference host, so match both names.
  assert.match(runtime, /if module\.is_some\(\)[\s\S]*withLocalInferenceHost\([\s\S]*FlutterLocalInferenceHost/);
  for (const method of ['ownerLocalInference', 'transcribeLocalSpeech', 'synthesizeLocalSpeech']) {
    assert.ok(channel.includes(`"${method}"`));
  }
  assert.match(channel, /"resultJson" to response/);
});

test('screen-awake hold is routed from the contract to the owner wake lock', () => {
  const contract = source('core/crates/foundation/host-contract/src/lib.rs');
  const host = source('hosts/android/src/system_operation.rs');
  const runtime = source('apps/flutter/native/operit-flutter-bridge/src/platform_runtime/android.rs');
  const channel = source(android + 'OwnerSystemCapabilityChannel.kt');
  const manifest = source('apps/flutter/app/android/app/src/main/AndroidManifest.xml');

  // The contract exposes the capability with a data type that names the mechanism honestly.
  assert.match(contract, /pub struct KeepScreenOnData/);
  assert.match(contract, /fn setKeepScreenOn\(&self, enabled: bool\) -> HostResult<KeepScreenOnData>/);

  // The Android host delegates to the owner bridge instead of fabricating a result.
  assert.match(host, /fn setKeepScreenOn\(&self, enabled: bool\) -> HostResult<KeepScreenOnData>/);
  assert.match(host, /self\.keepScreenOn/);
  assert.match(host, /withKeepScreenOn/);

  // The assembly wires the owner callback for both runtime shapes.
  assert.match(runtime, /withKeepScreenOn\(Arc::new\(ownerKeepScreenOn\)\)/);
  assert.match(runtime, /"set_keep_screen_on"/);

  // The owner applies a SCREEN_DIM wake lock so the display dims but never turns off.
  assert.match(channel, /"set_keep_screen_on" -> systemSetKeepScreenOn/);
  assert.match(channel, /PowerManager\.SCREEN_DIM_WAKE_LOCK/);
  assert.match(channel, /setReferenceCounted\(false\)/);
  assert.match(channel, /"mechanism"/);

  // Holding a wake lock requires the permission to be declared by the app itself.
  assert.match(manifest, /android\.permission\.WAKE_LOCK/);
});

test('screen-awake hold is exposed to plugins and the AI tool catalog', () => {
  const sdkSystem = source('core/crates/plugin/sdk/src/js_sdk/system.rs');
  const bindings = source('core/crates/plugin/sdk/src/js_sdk/runtime_bindings.rs');
  const toolTypes = source('core/crates/plugin/sdk/src/js_sdk/tool_types.rs');
  const prompts = source('core/crates/provider/services/src/chat/config/SystemToolPromptsInternal.rs');
  const toolPackage = source('plugins/packages/buildin/system_tools.ts');

  assert.match(sdkSystem, /fn setKeepScreenOn\(&self, enabled: bool\) -> JsFuture<KeepScreenOnData>/);
  assert.match(bindings, /method: "setKeepScreenOn", target: BuiltinToolName::SetKeepScreenOn/);
  assert.match(toolTypes, /pub set_keep_screen_on: KeepScreenOnData/);
  assert.match(toolPackage, /exports\.set_keep_screen_on/);
  // Both prompt languages must list the tool, or the model never sees it.
  const listed = prompts.match(/"set_keep_screen_on"/g) || [];
  assert.equal(listed.length, 2, 'set_keep_screen_on must appear in both prompt catalogs');
});

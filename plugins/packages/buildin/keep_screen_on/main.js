/* METADATA
{
    "name": "keep_screen_on",
    "display_name": { "zh": "任务运行保持屏幕常亮", "en": "Keep screen on while running" },
    "description": {
        "zh": "Agent 任务运行期间保持屏幕不锁屏、不熄屏；屏幕仍可照常变暗。任务结束自动释放。",
        "en": "Hold the screen on while an agent task runs so it does not lock or turn off; the display may still dim. Released automatically when the task ends."
    },
    "enabledByDefault": true,
    "category": "System",
    "tools": [
        { "name": "keep_screen_on_status", "display": {"label": {"zh": "查询常亮状态", "en": "Keep-screen-on status"}, "icon": "screen"}, "description": { "zh": "查看当前是否因任务运行而保持屏幕常亮。", "en": "Report whether the screen is currently held on for a running task." }, "parameters": [] }
    ]
}
*/

/**
 * Keeps the display awake while an agent task runs, and releases it when the task ends.
 *
 * The host provides the hold through Tools.System.setKeepScreenOn, which uses a dim-allowing
 * wake lock: the screen may dim but never turns off or locks. This package decides *when* to
 * hold and release, driven by chat runtime state changes rather than a fixed timer.
 *
 * This is a ToolPkg directory archive rather than a standalone `.js` package because only a
 * ToolPkg has its main script executed: the host runs `registerToolPkg`, which is where the
 * runtime hook is bound. A standalone package has its METADATA read but its script never runs,
 * so a hook registered there would silently never fire.
 */

/** Remembers the last state applied, so repeated events do not re-acquire the same hold. */
let lastApplied = null;
/** Records the last observed runtime state, for the status tool. */
let lastState = null;
/** Records the most recent host-reported mechanism, for the status tool. */
let lastMechanism = null;
/** Records why the last transition happened, for the status tool. */
let lastReason = null;

/** Applies the requested hold only when the desired state actually changes. */
async function applyHold(enabled, reason) {
    if (lastApplied === enabled) return;
    try {
        const result = await Tools.System.setKeepScreenOn(enabled);
        lastApplied = result.enabled;
        lastMechanism = result.mechanism;
        lastReason = reason;
    } catch (error) {
        // A host without the capability must not break the chat runtime hook.
        lastApplied = null;
        lastMechanism = "unavailable";
        lastReason = `${reason} (failed: ${String(error)})`;
    }
}

/**
 * Reacts to chat runtime state changes.
 *
 * A task is considered running whenever the runtime reports active work, which covers model
 * turns, tool execution, and plan execution. Terminal states release the hold so normal
 * screen-off behavior returns as soon as the task stops.
 */
async function onChatRuntimeStateChanged(event) {
    const payload = event && event.payload ? event.payload : {};
    const state = payload.state ?? "unknown";
    const isActive = payload.isActive === true;
    lastState = state;

    if (isActive) {
        await applyHold(true, `runtime ${state}`);
        return;
    }

    // Idle, completed and error all mean the task is no longer running.
    if (state === "idle" || state === "completed" || state === "error") {
        await applyHold(false, `runtime ${state}`);
    }
}

/** Reports the current hold and the last observed runtime state. */
async function keep_screen_on_status() {
    const state = lastState ?? "unknown";
    if (lastApplied === true) {
        return {
            success: true,
            message: `屏幕保持常亮中（mechanism: ${lastMechanism ?? "unknown"}）`,
            data: { held: true, mechanism: lastMechanism, runtimeState: state, reason: lastReason },
        };
    }
    if (lastApplied === false) {
        return {
            success: true,
            message: "屏幕常亮已释放",
            data: { held: false, mechanism: lastMechanism, runtimeState: state, reason: lastReason },
        };
    }
    return {
        success: true,
        message: "尚未触发过屏幕常亮",
        data: { held: null, mechanism: lastMechanism, runtimeState: state, reason: lastReason },
    };
}

/**
 * Registers this package's runtime hook.
 *
 * The host executes this export while loading the ToolPkg, so the callback is bound to the live
 * chat runtime before any state change arrives.
 */
exports.registerToolPkg = function registerToolPkg() {
    ToolPkg.registerChatRuntimeHook({
        id: "keep-screen-on",
        function: onChatRuntimeStateChanged,
    });
    return true;
};

exports.keep_screen_on_status = (params) => completeTool(keep_screen_on_status, params);

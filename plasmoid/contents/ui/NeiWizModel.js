.pragma library

function clampBrightness(value) {
    const number = Math.round(Number(value));
    if (!isFinite(number)) {
        return 100;
    }
    return Math.max(1, Math.min(100, number));
}

function applyState(row, state) {
    if (!row || !state || row.busy) {
        return null;
    }
    return {
        online: state.online === true,
        on: state.on === true,
        brightness: clampBrightness(state.brightness),
        mac: typeof state.mac === "string" ? state.mac : "",
    };
}

function shouldApplyRefresh(generation, currentGeneration) {
    return generation === currentGeneration;
}

import { clamp } from "../util/math.js";
import { fmtTime } from "../util/format.js";

export class UIController {
  constructor(els, settings, stats) {
    this.els = els;
    this.settings = settings;
    this.stats = stats;
    this.draft = {
      uiOpacity: this.settings.value.uiOpacity,
      speedLevel: this.settings.value.asteroidSpeedLevel,
      difficultyProgression: this.settings.value.difficultyProgression,
    };

    this.refreshLastResult();
    this.refreshVersion();
  }

  showStart() {
    this.els.startScreen.style.display = "grid";
    this.els.quitBtn.style.display = "none";
    this.els.pauseBtn.style.display = "none";
  }

  hideStart() {
    this.els.startScreen.style.display = "none";
    this.els.quitBtn.style.display = "grid";
    this.els.pauseBtn.style.display = "grid";
  }

  refreshLastResult() {
    const r = this.stats.lastResult;
    if (!r) {
      this.els.lastBox.textContent = "Última partida: (ainda não jogada)";
      return;
    }

    const clicks = r.clicks ?? 0;
    const destroyed = r.destroyed ?? 0;
    const acc = clicks > 0 ? Math.round((destroyed / clicks) * 100) : 0;

    this.els.lastBox.textContent =
      `Última partida\n` +
      `Destruídos: ${destroyed}\n` +
      `Fugas: ${r.misses}\n` +
      `Cliques: ${clicks}\n` +
      `Precisão: ${acc}%\n` +
      `Tempo: ${fmtTime(r.timeSec)}`;
  }

  syncFromSettings() {
    const op = clamp(
      Math.round((this.settings.value.uiOpacity * 100) / 20) * 20,
      20,
      100,
    );
    this.els.opacityRange.value = String(op);
    this.els.opacityOut.textContent = `${op}%`;

    const lvl = Math.round(this.settings.value.asteroidSpeedLevel);
    this.els.speedRange.value = String(lvl);
    this.els.speedOut.textContent = `Nível ${lvl}`;

    const on = !!this.settings.value.difficultyProgression;
    this.els.difficultyToggle.checked = on;
  }

  beginDraftFromSettings() {
    this.draft.uiOpacity = this.settings.value.uiOpacity;
    this.draft.speedLevel = this.settings.value.asteroidSpeedLevel;

    // Reflete no modal
    const op = clamp(
      Math.round((this.settings.value.uiOpacity * 100) / 20) * 20,
      20,
      100,
    );
    this.els.opacityRange.value = String(op);
    this.els.opacityOut.textContent = `${op}%`;

    const lvl = Math.round(this.draft.speedLevel);
    this.els.speedRange.value = String(lvl);
    this.els.speedOut.textContent = `Nível ${lvl}`;

    const on = !!this.draft.difficultyProgression;
    this.els.difficultyToggle.checked = on;
  }

  updateDraftDifficultyFromUI() {
    const on = !!this.els.difficultyToggle.checked;
    this.draft.difficultyProgression = on;
  }

  updateDraftOpacityFromUI() {
    const raw = Number(this.els.opacityRange.value); // 20..100, step 20
    const v01 = clamp(raw / 100, 0.2, 1);
    this.draft.uiOpacity = v01;
    this.els.opacityOut.textContent = `${raw}%`;
  }

  updateDraftSpeedFromUI() {
    const lvl = clamp(Number(this.els.speedRange.value), 1, 5);
    this.draft.speedLevel = lvl;
    this.els.speedOut.textContent = `Nível ${lvl}`;
  }

  applyDraft() {
    this.settings.set({
      uiOpacity: this.draft.uiOpacity,
      asteroidSpeedLevel: this.draft.speedLevel,
      difficultyProgression: this.draft.difficultyProgression,
    });

    // Mantém UI consistente
    this.syncFromSettings();
  }

  async refreshVersion() {
    if (!this.els.versionBox) return;

    try {
      const res = await fetch(`./version.json?ts=${Date.now()}`, {
        cache: "no-store",
      });
      if (!res.ok) throw new Error(`version.json status ${res.status}`);

      const data = await res.json();
      const version = data.version || "0.0.0";
      const build = data.build ?? 0;
      this.els.versionBox.textContent = `Versão ${version}+build.${build}`;
    } catch {
      this.els.versionBox.textContent = "Versão local";
    }
  }
}

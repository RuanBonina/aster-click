import { Storage } from "./Storage.js";
import { clamp } from "../util/math.js";

export class SettingsManager {
  constructor(root) {
    this.root = root;
    this.value = {
      uiOpacity: 1,
      asteroidSpeedLevel: 3,
      difficultyProgression: true,
    };
  }

  set(patch) {
    this.value = { ...this.value, ...patch };
    this.applyToDOM();
    Storage.saveSettings(this.value);
  }

  applyToDOM() {
    this.root.style.setProperty("--uiOpacity", String(this.value.uiOpacity));
  }

  load() {
    const saved = Storage.loadSettings();
    if (saved && typeof saved.uiOpacity === "number") {
      this.value.uiOpacity = clamp(saved.uiOpacity, 0.2, 1);
    }
    if (saved && typeof saved.asteroidSpeedLevel === "number") {
      this.value.asteroidSpeedLevel = clamp(saved.asteroidSpeedLevel, 1, 5);
    }
    if (saved && typeof saved.difficultyProgression === "boolean") {
      this.value.difficultyProgression = saved.difficultyProgression;
    }
    this.applyToDOM();
  }

  getAsteroidSpeedMul() {
    const map = [1.0, 1.5, 2.0, 3.0, 4.0];
    const idx = Math.round(this.value.asteroidSpeedLevel) - 1;
    return map[idx] ?? 1.0;
  }
}

import { SettingsManager } from "../config/SettingsManager.js";
import { Fullscreen } from "../services/Fullscreen.js";
import { Input } from "./Input.js";
import { RunClock } from "./RunClock.js";
import { Renderer } from "./Renderer.js";
import { AsteroidSystem } from "../systems/AsteroidSystem.js";
import { ParticlesSystem } from "../systems/ParticlesSystem.js";
import { StatsSystem } from "../systems/StatsSystem.js";
import { UIController } from "../ui/UIController.js";

export class Game {
  constructor({ canvas, ctx, hud, uiEls }) {
    this.canvas = canvas;
    this.ctx = ctx;

    this.w = 0;
    this.h = 0;
    this.dpr = 1;

    this.settings = new SettingsManager(document.documentElement);
    this.input = new Input();
    this.clock = new RunClock();
    this.stats = new StatsSystem();
    this.particles = new ParticlesSystem();
    this.asteroids = new AsteroidSystem(
      () => ({ w: this.w, h: this.h }),
      () => this.settings.getAsteroidSpeedMul() * this.dynamicSpeedMul,
    );
    this.confirmPending = false;
    this.dynamicSpeedMul = 1;
    this.stars = [];
    this.renderer = new Renderer({ ctx, hud }, this.settings);
    this.ui = new UIController(uiEls, this.settings, this.stats);

    this.uiEls = uiEls;
    this.closeCustomHelpTooltips = () => {};
    this.state = "START";
    this.lastT = performance.now();

    this.settings.load();
    this.ui.syncFromSettings();
    this.input.attachCanvas(this.canvas);

    this.resize();
    window.addEventListener("resize", () => this.resize());

    this.bindUI(uiEls);

    this.ui.showStart();
    this.tick = this.tick.bind(this);
    requestAnimationFrame(this.tick);
  }

  bindUI(els) {
    const closeConfirm = () => this.closeConfirmEnd();

    if (els.confirmModal) {
      const closeConfirm = () => this.closeConfirmEnd();

      els.confirmCloseBtn?.addEventListener("click", closeConfirm);
      els.confirmCancelBtn?.addEventListener("click", closeConfirm);
      els.confirmBackdrop?.addEventListener("click", closeConfirm);

      els.confirmEndBtn.addEventListener("click", () => {
        this.confirmPending = false;
        els.confirmModal.style.display = "none";
        this.end();
      });
    }

    // START/QUIT
    els.startBtn.addEventListener("click", () => this.start());
    els.quitBtn.addEventListener("click", () => this.openConfirmEnd());

    // MODAL
    const openModal = () => this.openCustomModal();
    const closeModal = () => this.closeCustomModal();

    els.pauseBtn.addEventListener("click", () => this.togglePause());
    els.customBtn.addEventListener("click", openModal);
    els.customCloseBtn.addEventListener("click", closeModal);
    this.bindCustomHelpTooltips();

    // SLIDERS (não aplicam direto; só atualizam o draft)
    els.opacityRange.addEventListener("input", () =>
      this.ui.updateDraftOpacityFromUI(),
    );
    els.speedRange.addEventListener("input", () =>
      this.ui.updateDraftSpeedFromUI(),
    );

    els.difficultyToggle.addEventListener("input", () =>
      this.ui.updateDraftDifficultyFromUI(),
    );

    // APPLY
    els.customApplyBtn.addEventListener("click", () => {
      this.ui.applyDraft();
      closeModal();
    });

    // FULLSCREEN (somente web desktop)
    const touchLikeDevice =
      /Android|iPhone|iPad|iPod|IEMobile|Opera Mini/i.test(navigator.userAgent) ||
      (window.matchMedia && window.matchMedia("(hover: none) and (pointer: coarse)").matches);
    const fullscreenAvailable = !!document.documentElement.requestFullscreen;

    if (!touchLikeDevice && fullscreenAvailable) {
      els.fsBtn.addEventListener("click", async () => {
        await Fullscreen.toggle();
      });

      document.addEventListener("fullscreenchange", () => {
        els.fsBtn.innerHTML = Fullscreen.iconHTML();
        this.resize();
      });

      els.fsBtn.innerHTML = Fullscreen.iconHTML();
      els.fsBtn.style.display = "grid";
    } else {
      els.fsBtn.style.display = "none";
    }

    closeModal();
  }

  resize() {
    this.dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
    this.w = Math.floor(window.innerWidth);
    this.h = Math.floor(window.innerHeight);
    this.canvas.width = Math.floor(this.w * this.dpr);
    this.canvas.height = Math.floor(this.h * this.dpr);
    this.canvas.style.width = this.w + "px";
    this.canvas.style.height = this.h + "px";
    this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    if (this.state === "PLAYING") this.generateStars();
  }

  generateStars() {
    const count = Math.max(80, Math.floor((this.w * this.h) / 12000));
    this.stars = Array.from({ length: count }, () => ({
      x: Math.random() * this.w,
      y: Math.random() * this.h,
      size: Math.random() < 0.82 ? 1 : 2,
      a: 0.35 + Math.random() * 0.55,
    }));
  }

  setPauseButtonPausedUI() {
    if (!this.uiEls.pauseBtn) return;
    this.uiEls.pauseBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path d="M8 6v12M16 6v12" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>
          </svg>`;
    this.uiEls.pauseBtn.title = "Pausar";
  }

  setPauseButtonPlayUI() {
    if (!this.uiEls.pauseBtn) return;
    this.uiEls.pauseBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path d="M8 6l12 6-12 6V6z" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/>
      </svg>`;
    this.uiEls.pauseBtn.title = "Retomar";
  }

  openCustomModal() {
    this.ui.beginDraftFromSettings();
    this.closeCustomHelpTooltips();
    if (this.uiEls.panel) this.uiEls.panel.style.display = "none";
    if (this.uiEls.customModal) this.uiEls.customModal.style.display = "grid";
  }

  closeCustomModal() {
    this.closeCustomHelpTooltips();
    if (this.uiEls.customModal) this.uiEls.customModal.style.display = "none";
    if (this.uiEls.panel) this.uiEls.panel.style.display = "";
  }

  bindCustomHelpTooltips() {
    const root = this.uiEls.customCard;
    if (!root) return;

    this.helpHintButtons = Array.from(root.querySelectorAll(".hintBtn"));
    this.closeCustomHelpTooltips = () => {
      this.helpHintButtons.forEach((btn) => btn.classList.remove("is-open"));
    };

    this.helpHintButtons.forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const shouldOpen = !btn.classList.contains("is-open");
        this.closeCustomHelpTooltips();
        if (shouldOpen) btn.classList.add("is-open");
      });
    });

    document.addEventListener("click", (e) => {
      if (!this.uiEls.customModal || this.uiEls.customModal.style.display === "none") return;
      if (root.contains(e.target)) return;
      this.closeCustomHelpTooltips();
    });

    document.addEventListener("touchstart", (e) => {
      if (!this.uiEls.customModal || this.uiEls.customModal.style.display === "none") return;
      if (e.target.closest(".hintBtn")) return;
      const hasOpenHint = this.helpHintButtons.some((btn) => btn.classList.contains("is-open"));
      if (!hasOpenHint) return;
      this.closeCustomHelpTooltips();
    }, { passive: true });
  }

  start() {
    this.stats.resetRun();
    this.particles.clear();
    this.asteroids.clear();
    this.dynamicSpeedMul = 1;
    this.generateStars();

    this.clock.start(performance.now());
    this.state = "PLAYING";
    this.ui.hideStart();

    this.uiEls.pauseBtn.style.display = "grid";
    this.setPauseButtonPausedUI();
  }

  end() {
    if (this.uiEls.confirmModal) this.uiEls.confirmModal.style.display = "none";
    this.confirmPending = false;

    if (this.state !== "PLAYING") return;

    const now = performance.now();
    const timeSec = this.clock.elapsedSeconds(now);
    this.clock.stop();

    this.stats.finalize(timeSec);
    this.ui.refreshLastResult();

    this.particles.clear();
    this.asteroids.clear();
    this.stars = [];

    this.state = "START";
    this.ui.showStart();

    this.uiEls.pauseBtn.style.display = "none";
    this.setPauseButtonPausedUI();
  }

  openConfirmEnd() {
    if (!this.uiEls.confirmModal) return;
    if (this.state !== "PLAYING") return;

    if (!this.clock.paused) {
      this.clock.togglePause(performance.now());
      this.setPauseButtonPlayUI();
    }

    this.confirmPending = true;
    this.uiEls.confirmModal.style.display = "block";

    if (this.uiEls.customModal) this.uiEls.customModal.style.display = "none";
  }

  closeConfirmEnd() {
    this.confirmPending = false;
    if (this.uiEls.confirmModal) this.uiEls.confirmModal.style.display = "none";

    if (this.state === "PLAYING" && this.clock.paused) {
      this.clock.togglePause(performance.now());
      this.setPauseButtonPausedUI();
    }
  }

  togglePause() {
    if (this.state !== "PLAYING") return;
    if (this.confirmPending) return;
    this.clock.togglePause(performance.now());
    if (this.clock.paused) this.setPauseButtonPlayUI();
    else this.setPauseButtonPausedUI();
  }

  update(dt) {
    if (this.state !== "PLAYING") return;
    if (this.clock.paused) return;

    const now = performance.now();
    const elapsed = this.clock.elapsedSeconds(now);

    if (this.settings.value.difficultyProgression) {
      this.dynamicSpeedMul = 1 + Math.floor(elapsed / 10) * 0.1;
      this.dynamicSpeedMul = Math.min(this.dynamicSpeedMul, 3.0);
    } else {
      this.dynamicSpeedMul = 1;
    }

    if (this.input.click) {
      this.stats.recordClick();

      const hit = this.asteroids.tryHit(this.input.click);

      if (hit.hit) {
        this.stats.recordDestroyed();
        this.particles.explode(hit.x, hit.y, hit.r);
      } else {
        // feedback de clique errado
        this.particles.ping(this.input.click.x, this.input.click.y);
      }
    }

    const res = this.asteroids.update(dt);
    if (res.missed) this.stats.recordMiss();

    this.particles.update(dt);
  }

  render(now) {
    this.renderer.clear(this.w, this.h);
    if (this.state === "PLAYING") this.renderer.drawStars(this.stars);
    this.renderer.drawAsteroid(this.asteroids.asteroid);
    this.renderer.drawParticles(this.particles.particles);
    this.renderer.drawRings(this.particles.rings);

    const timeSec =
      this.state === "PLAYING" ? this.clock.elapsedSeconds(now) : 0;

    this.renderer.drawHUD({
      destroyed: this.stats.destroyed,
      misses: this.stats.misses,
      timeSec,
      paused: this.clock.paused,
    });
  }

  tick(t) {
    const dt = Math.min(0.033, (t - this.lastT) / 1000);
    this.lastT = t;

    if (this.input.togglePause) this.togglePause();

    if (this.confirmPending) {
      this.input.resetFrame();
      this.render(t);
      requestAnimationFrame(this.tick);
      return;
    }

    if (this.input.quit) this.openConfirmEnd();

    this.update(dt);
    this.render(t);

    this.input.resetFrame();
    requestAnimationFrame(this.tick);
  }
}

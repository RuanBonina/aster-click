import { clamp } from "../util/math.js";
import { fmtTime } from "../util/format.js";

export class Renderer {
  constructor({ ctx, hud }, settings) {
    this.ctx = ctx;
    this.hud = hud;
    this.settings = settings;
  }

  clear(w, h) {
    this.ctx.clearRect(0, 0, w, h);
  }

  drawStars(stars) {
    if (!stars || stars.length === 0) return;
    const ctx = this.ctx;

    for (const s of stars) {
      ctx.globalAlpha = s.a;
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(s.x, s.y, s.size, s.size);
    }
    ctx.globalAlpha = 1;
  }

  drawAsteroid(a) {
    if (!a) return;
    const ctx = this.ctx;

    ctx.save();
    ctx.translate(a.x, a.y);
    ctx.rotate(a.ang);

    ctx.beginPath();
    for (let i = 0; i < a.points.length; i++) {
      const p = a.points[i];
      const px = Math.cos(p.a) * p.rr;
      const py = Math.sin(p.a) * p.rr;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();

    ctx.strokeStyle = "#d6d6d6";
    ctx.lineWidth = 2;
    ctx.globalAlpha = this.settings.value.uiOpacity;
    ctx.stroke();

    ctx.shadowColor = "rgba(255,255,255,0.12)";
    ctx.shadowBlur = 10;
    ctx.stroke();

    ctx.globalAlpha = 1;
    ctx.restore();
  }

  drawParticles(particles) {
    const ctx = this.ctx;
    const uiOp = this.settings.value.uiOpacity;

    for (const p of particles) {
      const k = 1 - p.t / p.life;
      ctx.globalAlpha = clamp(k, 0, 1) * uiOp;
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  drawRings(rings) {
    const ctx = this.ctx;
    const uiOp = this.settings.value.uiOpacity;

    for (const r of rings) {
      const k = 1 - r.t / r.life; // 1..0
      const radius = r.r0 + (1 - k) * (r.r1 - r.r0);

      ctx.globalAlpha = k * uiOp;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(r.x, r.y, radius, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  drawHUD({ destroyed, misses, timeSec, paused }) {
    const t = fmtTime(timeSec);
    this.hud.textContent =
      `Destruídos: ${destroyed}\n` +
      `Fugas: ${misses}\n` +
      `Tempo: ${t}` +
      (paused ? `\nPAUSADO` : "");
  }
}

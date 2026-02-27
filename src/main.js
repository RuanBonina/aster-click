import { Game } from "./core/Game.js";

const canvas = document.getElementById("c");
const ctx = canvas.getContext("2d");
const hud = document.getElementById("hud");

const uiEls = {
  pauseBtn: document.getElementById("pauseBtn"),
  fsBtn: document.getElementById("fsBtn"),
  quitBtn: document.getElementById("quitBtn"),

  startScreen: document.getElementById("startScreen"),
  panel: document.getElementById("panel"),
  startBtn: document.getElementById("startBtn"),
  customBtn: document.getElementById("customBtn"),
  versionBox: document.getElementById("version"),
  lastBox: document.getElementById("last"),

  customModal: document.getElementById("customModal"),
  customCard: document.getElementById("customCard"),
  customCloseBtn: document.getElementById("customCloseBtn"),
  customApplyBtn: document.getElementById("customApplyBtn"),

  opacityRange: document.getElementById("opacityRange"),
  opacityOut: document.getElementById("opacityOut"),
  speedRange: document.getElementById("speedRange"),
  speedOut: document.getElementById("speedOut"),

  confirmModal: document.getElementById("confirmModal"),
  confirmBackdrop: document.getElementById("confirmBackdrop"),
  confirmCloseBtn: document.getElementById("confirmCloseBtn"),
  confirmCancelBtn: document.getElementById("confirmCancelBtn"),
  confirmEndBtn: document.getElementById("confirmEndBtn"),

  difficultyToggle: document.getElementById("difficultyToggle"),
};

new Game({ canvas, ctx, hud, uiEls });

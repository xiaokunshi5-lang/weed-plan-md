/**
 * =============================================================================
 * 极轻量可插拔 UI 触感与合成音效工具包: scripts/ui_tactile_kit.js
 * 适用范围: UI审美与开源组件借鉴工作流 (v1.0)
 * 核心特性:
 *   1. 【默认静默 (Opt-In Only)】: 默认 mode = 'disabled'，绝不擅自发声干扰同声传译/语音等项目。
 *   2. 【零外部音频文件 (0 KB MP3/WAV)】: 采用浏览器原生 Web Audio API 数学合成 6 种微交互音效。
 *   3. 【帧级声画同步】: 按压音效绑定 pointerdown，与 CSS :active scale(0.97) 0ms 同帧触发。
 *   4. 【无障碍与静音记忆】: 自动尊重 prefers-reduced-motion，支持 localStorage 一键持久化静音。
 * =============================================================================
 */

export class UISoundEngine {
  /**
   * @param {'disabled' | 'subtle' | 'immersive'} initialMode
   *   - 'disabled' : 完全禁音（默认！适用于同声传译、ASR语音、会议、或用户选择纯视觉模式）
   *   - 'subtle'   : 轻量模式（仅保留关键状态切换与成功/错误反馈音）
   *   - 'immersive': 沉浸打击模式（开启按钮按压微咔声、气泡声、拨片声与重打击反馈）
   */
  constructor(initialMode = 'disabled') {
    this.ctx = null;
    this.storageKey = 'agy_ui_sound_mode';
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(this.storageKey) : null;
    this.mode = saved || initialMode;
  }

  /** 设置音效模式并持久化: 'disabled' | 'subtle' | 'immersive' */
  setMode(mode) {
    this.mode = mode;
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(this.storageKey, mode);
    }
  }

  /** 检查当前是否允许播放指定级别的音效 */
  canPlay(level = 'immersive') {
    if (this.mode === 'disabled') return false;
    if (typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      return false;
    }
    if (level === 'immersive' && this.mode !== 'immersive') return false;
    return true;
  }

  /** 必须在用户手势事件 (pointerdown / click) 内惰性唤醒 AudioContext */
  ensureContext() {
    if (!this.ctx && typeof window !== 'undefined') {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) this.ctx = new AudioCtx();
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
    return this.ctx;
  }

  /** 1. 清脆微咔声 (Click - 28ms): 绑定 pointerdown，对齐 :active scale(0.97) 第一帧 */
  playClick() {
    if (!this.canPlay('immersive')) return;
    const ctx = this.ensureContext();
    if (!ctx) return;

    const t = ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'sine';
    osc.frequency.setValueAtTime(800, t);
    osc.frequency.exponentialRampToValueAtTime(140, t + 0.028);

    gain.gain.setValueAtTime(0.12, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.028);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + 0.028);
  }

  /** 2. 轻盈气泡声 (Pop - 45ms): 对齐 Popover / Modal / 浮层展开第一帧 (Scale 0.95 -> 1) */
  playPop() {
    if (!this.canPlay('immersive')) return;
    const ctx = this.ensureContext();
    if (!ctx) return;

    const t = ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'sine';
    osc.frequency.setValueAtTime(320, t);
    osc.frequency.exponentialRampToValueAtTime(880, t + 0.045);

    gain.gain.setValueAtTime(0.14, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.045);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + 0.045);
  }

  /** 3 & 4. 机械拨片开关声 (Toggle ON / OFF - 55ms): 开启八度上扬，关闭八度下潜 */
  playToggle(isOn = true) {
    if (!this.canPlay('subtle')) return;
    const ctx = this.ensureContext();
    if (!ctx) return;

    const t = ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(440, t);
    osc.frequency.exponentialRampToValueAtTime(isOn ? 880 : 220, t + 0.055);

    gain.gain.setValueAtTime(0.12, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.055);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + 0.055);
  }

  /** 5. 达成双音和弦 (Success Chime - 160ms): C5 (523.25Hz) -> E5 (659.25Hz) */
  playSuccess() {
    if (!this.canPlay('subtle')) return;
    const ctx = this.ensureContext();
    if (!ctx) return;

    const notes = [523.25, 659.25];
    notes.forEach((freq, idx) => {
      const t = ctx.currentTime + idx * 0.06;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, t);

      gain.gain.setValueAtTime(0.12, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.1);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + 0.1);
    });
  }

  /** 6. 低频阻尼闷响 (Error / Shake Thud - 140ms): 双脉冲严格对齐 Shake 抖动波峰 (0ms & 70ms) */
  playError() {
    if (!this.canPlay('subtle')) return;
    const ctx = this.ensureContext();
    if (!ctx) return;

    [0, 0.07].forEach((offset) => {
      const t = ctx.currentTime + offset;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = 'triangle';
      osc.frequency.setValueAtTime(150, t);
      osc.frequency.exponentialRampToValueAtTime(60, t + 0.06);

      gain.gain.setValueAtTime(0.18, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.06);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + 0.06);
    });
  }
}

export const uiSound = new UISoundEngine('disabled');

/**
 * 声明式 DOM 声画同步绑定器
 * 用法: 在 HTML 元素上添加 data-ui-sound="click|pop|toggle|success|error"
 * 按压类音效自动绑定在 pointerdown 上，实现与 CSS :active 缩放的 0ms 同帧同步！
 */
export function bindDeclarativeUISounds(root = document) {
  root.addEventListener('pointerdown', (e) => {
    const el = e.target.closest?.('[data-ui-sound]');
    if (!el || el.disabled) return;
    const kind = el.getAttribute('data-ui-sound');
    if (kind === 'click') uiSound.playClick();
    else if (kind === 'pop') uiSound.playPop();
  });

  root.addEventListener('click', (e) => {
    const el = e.target.closest?.('[data-ui-sound]');
    if (!el || el.disabled) return;
    const kind = el.getAttribute('data-ui-sound');
    if (kind === 'toggle') {
      const isOn = el.getAttribute('aria-checked') === 'true' || el.classList.contains('is-on');
      uiSound.playToggle(isOn);
    } else if (kind === 'success') {
      uiSound.playSuccess();
    } else if (kind === 'error') {
      uiSound.playError();
    }
  });
}

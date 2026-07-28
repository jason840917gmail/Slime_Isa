import Phaser from 'phaser';
import { Friend } from './Friend';
import { resolveScreenUiDepth } from './presentation/WorldDepth';

type ReplyGroup = {
  keywords: string[];
  lines: string[];
};

const REPLY_GROUPS: ReplyGroup[] = [
  {
    keywords: ['hi', 'hello', 'hey', 'sup', 'yo', 'howdy'],
    lines: ['hi there!', 'hey hey!', 'hello!', 'yo!', 'heya!'],
  },
  {
    keywords: ['bye', 'cya', 'see you', 'goodbye', 'later'],
    lines: ['see you later!', 'bye bye!', 'take care!', 'catch you soon!'],
  },
  {
    keywords: ['thanks', 'thank', 'thx', 'ty'],
    lines: ['no problem!', 'anytime!', 'yw!', 'happy to help!'],
  },
  {
    keywords: ['food', 'hungry', 'eat', 'berry', 'berries', 'snack'],
    lines: ['love those purple berries!', 'im starving', 'got any snacks?'],
  },
  {
    keywords: ['house', 'home', 'live', 'place'],
    lines: ['my house is just over there!', 'home sweet home', 'love my little place'],
  },
  {
    keywords: ['friend', 'buddy', 'pal', 'bestie'],
    lines: ['were besties!', 'friends forever!', 'love hanging out with you'],
  },
  {
    keywords: ['love', 'like', 'cool', 'awesome', 'great', 'nice'],
    lines: ['aww thanks!', 'right?!', 'so glad you think so!', 'hehe'],
  },
  {
    keywords: ['?', 'how', 'what', 'why', 'where', 'when'],
    lines: ['hmm, good question!', 'not sure tbh', 'idk lol', 'beats me!', 'good question'],
  },
  {
    keywords: ['sad', 'bad', 'tired', 'sleep', 'bed'],
    lines: ['oh no! hope youre ok', 'maybe get some rest?', 'rough day huh'],
  },
];

const FALLBACK_LINES = [
  'haha nice',
  'totally',
  'lol',
  'right??',
  'uh huh',
  'same',
  'for real',
  'wild',
  'cool!',
  'yeah',
  'mhm',
  'hehe',
];

const FALLBACK_NAMES = [
  'pip', 'moss', 'fern', 'bramble', 'clover', 'briar', 'wisp', 'sprig', 'dusty', 'robin',
];

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export class ChatUI {
  private inputEl: HTMLInputElement;
  private logTexts: Phaser.GameObjects.Text[] = [];
  private box: Phaser.GameObjects.Graphics;
  private hintText: Phaser.GameObjects.Text;
  private isOpen = false;
  private onOpenChange?: (open: boolean) => void;
  private getFriends: () => Friend[];
  private getPlayerName: () => string;
  private scene: Phaser.Scene;
  private readonly maxLog = 5;
  private handleDocKeydown: (e: KeyboardEvent) => void;

  constructor(
    scene: Phaser.Scene,
    getFriends: () => Friend[],
    getPlayerName: () => string,
    onOpenChange?: (open: boolean) => void,
  ) {
    this.scene = scene;
    this.getFriends = getFriends;
    this.getPlayerName = getPlayerName;
    this.onOpenChange = onOpenChange;

    const cam = scene.cameras.main;

    this.box = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(20)).setVisible(false);

    this.hintText = scene.add
      .text(16, cam.height - 30, 'Press  /  to chat', {
        fontFamily: FONT,
        fontSize: '14px',
        color: '#ffd277',
        stroke: '#081022',
        strokeThickness: 3,
      })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(21));

    this.inputEl = document.createElement('input');
    this.inputEl.type = 'text';
    this.inputEl.maxLength = 80;
    this.inputEl.autocomplete = 'off';
    this.inputEl.spellcheck = false;
    this.inputEl.placeholder = 'Say something to a friend...';
    this.inputEl.style.cssText = [
      'position: fixed',
      'left: 50%',
      'bottom: 24px',
      'transform: translateX(-50%)',
      'width: min(480px, 90vw)',
      'padding: 10px 14px',
      'font: 16px Trebuchet MS, "Segoe UI Variable", sans-serif',
      'border: 2px solid #73e2b1',
      'border-radius: 10px',
      'background: rgba(10, 31, 21, 0.96)',
      'color: #fff',
      'outline: none',
      'z-index: 1000',
      'display: none',
      'box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4)',
    ].join(';');
    document.body.appendChild(this.inputEl);

    this.inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this.sendMessage();
      }
      e.stopPropagation();
    });

    this.inputEl.addEventListener('blur', () => {
      if (this.isOpen) this.close();
    });

    this.handleDocKeydown = (e: KeyboardEvent) => {
      if (!this.isOpen) return;
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        this.close();
      }
    };
    document.addEventListener('keydown', this.handleDocKeydown, true);

    const slashKey = scene.input.keyboard?.addKey(191);
    if (slashKey) {
      slashKey.on('down', () => {
        if (!this.isOpen) this.open();
      });
    }

    this.handleResize(cam.width, cam.height);
    scene.scale.on('resize', (size: Phaser.Structs.Size) => this.handleResize(size.width, size.height));
  }

  isChatOpen(): boolean {
    return this.isOpen;
  }

  open(): void {
    if (this.isOpen) return;
    this.isOpen = true;
    this.inputEl.style.display = 'block';
    this.inputEl.value = '';
    this.inputEl.focus();
    this.hintText.setVisible(false);
    this.box.setVisible(true);
    this.drawBox();
    this.onOpenChange?.(true);
  }

  close(): void {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.inputEl.style.display = 'none';
    this.inputEl.blur();
    this.hintText.setVisible(true);
    this.box.setVisible(true);
    this.drawBox();
    this.onOpenChange?.(false);
  }

  private sendMessage(): void {
    const msg = this.inputEl.value.trim();
    if (!msg) {
      this.close();
      return;
    }
    this.addLog(this.getPlayerName(), msg, 0x72d8ff);
    this.close();

    const friends = this.getFriends();
    if (friends.length === 0) return;

    const reply = this.pickReply(msg);
    const delay = Phaser.Math.Between(700, 1400);

    this.scene.time.delayedCall(delay, () => {
      const name = FALLBACK_NAMES[Phaser.Math.Between(0, FALLBACK_NAMES.length - 1)];
      this.addLog(name, reply, 0xffb347);
    });
  }

  private pickReply(msg: string): string {
    const lower = msg.toLowerCase();
    for (const group of REPLY_GROUPS) {
      if (group.keywords.some((k) => lower.includes(k))) {
        return group.lines[Phaser.Math.Between(0, group.lines.length - 1)];
      }
    }
    return FALLBACK_LINES[Phaser.Math.Between(0, FALLBACK_LINES.length - 1)];
  }

  private addLog(name: string, text: string, color: number): void {
    const cam = this.scene.cameras.main;
    const colorHex = '#' + color.toString(16).padStart(6, '0');
    const line = this.scene.add.text(0, 0, `${name}: ${text}`, {
      fontFamily: FONT,
      fontSize: '15px',
      color: colorHex,
      stroke: '#0b1020',
      strokeThickness: 3,
      wordWrap: { width: cam.width - 48 },
    }).setScrollFactor(0).setDepth(resolveScreenUiDepth(21));

    this.logTexts.push(line);
    while (this.logTexts.length > this.maxLog) {
      const old = this.logTexts.shift();
      old?.destroy();
    }
    this.layoutLog();
    this.drawBox();
  }

  private layoutLog(): void {
    const cam = this.scene.cameras.main;
    const x = 24;
    let y = cam.height - 70;
    for (let i = this.logTexts.length - 1; i >= 0; i -= 1) {
      const t = this.logTexts[i];
      t.setPosition(x, y - t.height);
      y -= t.height + 4;
    }
  }

  private drawBox(): void {
    const cam = this.scene.cameras.main;
    this.box.clear();
    if (!this.isOpen && this.logTexts.length === 0) return;

    let topY = cam.height - 30;
    if (this.logTexts.length > 0) {
      const first = this.logTexts[0];
      topY = first.y - 6;
    }
    const boxH = cam.height - 24 - topY;
    if (boxH <= 0) return;

    this.box.fillStyle(0x0b1020, 0.78);
    this.box.fillRoundedRect(12, topY, cam.width - 24, boxH, 10);
    this.box.lineStyle(2, 0x73e2b1, 0.9);
    this.box.strokeRoundedRect(12, topY, cam.width - 24, boxH, 10);
  }

  private handleResize(_w: number, h: number): void {
    this.hintText.setPosition(16, h - 30);
    this.layoutLog();
    this.drawBox();
  }

  destroy(): void {
    document.removeEventListener('keydown', this.handleDocKeydown, true);
    this.inputEl.remove();
    this.box.destroy();
    this.hintText.destroy();
    this.logTexts.forEach((t) => t.destroy());
  }
}

// Finn in pixels: the one source for the 8-bit fish, his moods and the small marks.
//
// It is a plain script so that it works two ways:
//   - in Node, through require(), to write the Swift sprite data and the app icon;
//   - in any page that loads it with a <script> tag, as window.Finn8.
//
// Change the art here, then regenerate App/UI/FinnSprites.swift and the app icon from it.
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Finn8 = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // ---------------------------------------------------------------- palette

  const P = {
    ink: '#181425', navy: '#262b44', slate: '#3a4466', steel: '#5a6988', mist: '#8b9bb4', cloud: '#c0cbdc', white: '#ffffff',
    deep: '#124e89', sea: '#0b6cab', water: '#0099db', aqua: '#2ce8f5',
    orange: '#f77622', light: '#feae34', yellow: '#fee761', rust: '#be4a2f', red: '#e43b44', pink: '#f6757a',
    cream: '#ead4aa', sand: '#c28569', green: '#63c74d', moss: '#3e8948', purple: '#b55088', lilac: '#a8b4f0',
  };

  // One letter per colour, used by every sprite below.
  const KEY = {
    K: P.ink, O: P.orange, L: P.light, Y: P.yellow, D: P.rust, W: P.white, B: P.ink, P: P.pink, M: P.ink,
    G: P.mist, U: P.water, A: P.aqua, R: P.purple, r: P.pink, S: P.steel, C: P.cloud, E: P.green, F: P.moss,
    N: P.navy, T: P.cream, Q: P.sand, V: P.lilac, X: P.red,
  };

  // ---------------------------------------------------------------- sprites

  // Builds a sprite from rows of letters. Every empty pixel that touches a filled one becomes outline.
  // The result is padded by one pixel on every side, so content pixel (0, 0) is drawn at (x, y).
  function makeSprite(name, rows, outline = true) {
    const width = rows[0].length;
    for (const row of rows) {
      if (row.length !== width) throw new Error(`Sprite ${name}: row "${row}" is ${row.length} wide, expected ${width}`);
    }
    const padded = ['.'.repeat(width + 2), ...rows.map((row) => `.${row}.`), '.'.repeat(width + 2)].map((row) => row.split(''));
    const out = padded.map((row) => row.slice());
    if (outline) {
      for (let y = 0; y < padded.length; y++) {
        for (let x = 0; x < width + 2; x++) {
          if (padded[y][x] !== '.') continue;
          const touches = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => {
            const row = padded[y + dy];
            return row && row[x + dx] && row[x + dx] !== '.';
          });
          if (touches) out[y][x] = 'K';
        }
      }
    }
    return { name, w: width, h: rows.length, px: out };
  }

  function drawSprite(ctx, sprite, x, y, scale = 1, flip = false) {
    const rows = sprite.px;
    const fullWidth = rows[0].length;
    for (let py = 0; py < rows.length; py++) {
      for (let px = 0; px < fullWidth; px++) {
        const letter = rows[py][px];
        if (letter === '.') continue;
        ctx.fillStyle = KEY[letter];
        const column = flip ? fullWidth - 1 - px : px;
        ctx.fillRect(x + (column - 1) * scale, y + (py - 1) * scale, scale, scale);
      }
    }
  }

  // The fish, 24 by 18, facing right. Only the fill is drawn here; the outline is added by makeSprite.
  const FISH_ROWS = [
    '........................',
    '............LLL.........',
    '...........LLOOO........',
    '.LL........OLLLOOOO.....',
    '.LLO.....OLLYYLOOOOOO...',
    '..LLO...OLLYLOOOWWWWOO..',
    '...LOO..OLLLOOOWWWWBWOO.',
    '....OOOOOOLOOOOWWWBBWOO.',
    '.....OOOOOOOLLOWWWBBWOO.',
    '....ODOOOOOLLYLOWWWWOOO.',
    '...ODO..OOOLLLOOOPPOOOM.',
    '..ODO...DOOLLOOOOOOOMM..',
    '.ODO.....DDOOOLLLLLOO...',
    '.OO........DDOOLLOO.....',
    '.............LO.........',
    '.............L..........',
    '........................',
    '........................',
  ];

  // The second tail frame: columns 0 to 6 of rows 3 to 13.
  const TAIL_B = [
    '.......',
    '.......',
    '.LLL...',
    '..LLOO.',
    '...OOOO',
    '.....OO',
    '...OOOO',
    '..ODDO.',
    '.OOO...',
    '.......',
    '.......',
  ];

  // Eyes are a 6 by 5 patch at column 15, row 5. One big eye carries every expression.
  const EYES = {
    normal: ['OWWWWO', 'WWWWBW', 'WWWBBW', 'WWWBBW', 'OWWWWO'],
    up: ['OWWBBO', 'WWWBBW', 'WWWWWW', 'WWWWWW', 'OWWWWO'],
    down: ['OWWWWO', 'WWWWWW', 'WWWWBW', 'WWWBBW', 'OWWBBO'],
    wide: ['OWWWWO', 'WWWBBW', 'WWBBBW', 'WWBBBW', 'OWWWWO'],
    small: ['OWWWWO', 'WWWWWW', 'WWWBWW', 'WWWWWW', 'OWWWWO'],
    half: ['OOOOOO', 'OKKKKO', 'WWWBBW', 'WWWBBW', 'OWWWWO'],
    happy: ['OOOOOO', 'OOKKOO', 'OKOOKO', 'OOOOOO', 'OOOOOO'],
    shut: ['OOOOOO', 'OOOOOO', 'OKKKKO', 'OOOOOO', 'OOOOOO'],
    // A brow that slopes down toward the nose, over a pupil looking ahead. Added for the focused mood.
    focus: ['KKOOOO', 'WWKKOO', 'WWWWKK', 'WWWBBW', 'OWWBBO'],
  };

  // Mouth pixels: [column, row, letter].
  const MOUTHS = {
    smile: [[22, 10, 'M'], [21, 11, 'M'], [20, 11, 'M']],
    open: [[22, 10, 'M'], [21, 10, 'M'], [21, 11, 'M'], [20, 11, 'O']],
    flat: [[22, 10, 'O'], [21, 11, 'M'], [20, 11, 'M']],
  };

  const fishCache = {};
  function fishSprite(tail, eye, mouth) {
    const key = `${tail}-${eye}-${mouth}`;
    if (fishCache[key]) return fishCache[key];
    const rows = FISH_ROWS.map((row) => row.split(''));
    if (tail) {
      for (let i = 0; i < TAIL_B.length; i++) {
        for (let x = 0; x < 7; x++) rows[3 + i][x] = TAIL_B[i][x];
      }
    }
    const patch = EYES[eye];
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) rows[5 + r][15 + c] = patch[r][c];
    }
    for (const [x, y, letter] of MOUTHS[mouth]) rows[y][x] = letter;
    fishCache[key] = makeSprite(`fish ${key}`, rows.map((row) => row.join('')));
    return fishCache[key];
  }

  const SPRITES = {
    bubble: makeSprite('bubble', ['...WWW...', '.WWWWWWW.', '.WWWWWWW.', 'WWWWWWWWW', 'WWWWWWWWW', 'WWWWWWWWW', '.WWWWWWW.', '.WWWWWWW.', '...WWW...']),
    popping: makeSprite('popping', ['...A.A...', '.A.....A.', '.........', 'A.......A', '.........', 'A.......A', '.........', '.A.....A.', '...A.A...'], false),
    sparkle: makeSprite('sparkle', ['..Y..', '..Y..', 'YYWYY', '..Y..', '..Y..'], false),
    spark: makeSprite('spark', ['.Y.', 'YWY', '.Y.'], false),
    ring5: makeSprite('ring5', ['.AAA.', 'A...A', 'A.W.A', 'A...A', '.AAA.'], false),
    ring3: makeSprite('ring3', ['.A.', 'A.A', '.A.'], false),
    page: makeSprite('page', ['WWWWW.', 'WWWWWW', 'WVVVVW', 'WWWWWW', 'WVVVWW', 'WWWWWW', 'WVVVVW', 'WWWWWW']),
    weed: makeSprite('weed', ['..E..', '.EE..', '.E...', '.EF..', '..EE.', '..E..', '.EE..', '.E...', '.EF..', '..EE.', '..E..', '.EE..', '.EF..', '..E..'], false),
    phone: makeSprite('phone', ['EEEEE', 'E...E', 'E...E', 'E...E', 'E...E', 'EEEEE', 'EEEEE'], false),
    cloudIcon: makeSprite('cloudIcon', ['..VV...', '.VVVVV.', 'VVVVVVV', 'VVVVVVV'], false),
    drop: makeSprite('drop', ['..U..', '..U..', '.UAU.', '.UAU.', 'UAAAU', 'UAAAU', '.UUU.'], false),
    lens: makeSprite('lens', ['.SSS....', 'SAAAS...', 'SAWAS...', 'SAAAS...', '.SSSD...', '....DD..', '.....DD.', '......D.']),
    cap: makeSprite('cap', ['....NNN....', '..NNNNNNN..', 'NNNNNNNNNNN', '..NNNNNNN.Y', '..NNNNNNN.Y', '..........Y']),
    // A sweatband across the forehead with its ties flying back. Drawn at column 7, row 2 of the fish (RIG).
    headband: makeSprite('headband', [
      'XX............',
      '..XXXXXXXXXXXX',
      'XX.XXXXXXXXWXX',
    ]),
    notTaught: makeSprite('notTaught', ['..G.G..', '.G.....', '......G', 'G......', '......G', '.G.....', '..G.G..'], false),
    taught: makeSprite('taught', ['..UUU..', '.UAAAU.', 'UAWAAAU', 'UAAAAAU', 'UAAAAAU', '.UAAAU.', '..UUU..'], false),
    recalled: makeSprite('recalled', ['..RRR..', '.RrrrR.', 'RrWrrrR', 'RrrRrrR', 'RrrrrrR', '.RrrrR.', '..RRR..'], false),
    mastered: makeSprite('mastered', ['..LLL..', '.LYYYL.', 'LYWYYYL', 'LYYYYYL', 'LYYYYYL', '.LYYYL.', '..LLL..'], false),
    // A lightbulb for Orla's bubble when she gives a hint.
    bulb: makeSprite('bulb', ['.YYY.', 'YWYYY', 'YWYYL', 'YYYYL', '.YLL.', '.SSS.', '..S..'], false),
  };

  // The cloud is built from three pixel circles, so it stays lumpy at any size.
  SPRITES.cloud = (() => {
    const width = 30, height = 15;
    const rows = [];
    for (let y = 0; y < height; y++) {
      let row = '';
      for (let x = 0; x < width; x++) {
        const inside = [[8, 9.5, 5.2], [15, 7, 6.6], [22, 9.5, 5.2]].some(([cx, cy, r]) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r) || (y >= 9 && y <= 13 && x >= 5 && x <= 25);
        row += inside && y <= 13 ? (y >= 12 ? 'C' : 'W') : '.';
      }
      rows.push(row);
    }
    return makeSprite('cloud', rows);
  })();

  // ---------------------------------------------------------------- font

  // A 5 by 7 pixel font. Lower case is drawn as upper case.
  const FONT_SOURCE = {
    A: '.###./#...#/#...#/#####/#...#/#...#/#...#', B: '####./#...#/#...#/####./#...#/#...#/####.',
    C: '.###./#...#/#..../#..../#..../#...#/.###.', D: '####./#...#/#...#/#...#/#...#/#...#/####.',
    E: '#####/#..../#..../####./#..../#..../#####', F: '#####/#..../#..../####./#..../#..../#....',
    G: '.###./#...#/#..../#.###/#...#/#...#/.###.', H: '#...#/#...#/#...#/#####/#...#/#...#/#...#',
    I: '.###./..#../..#../..#../..#../..#../.###.', J: '..###/...#./...#./...#./...#./#..#./.##..',
    K: '#...#/#..#./#.#../##.../#.#../#..#./#...#', L: '#..../#..../#..../#..../#..../#..../#####',
    M: '#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#', N: '#...#/##..#/#.#.#/#..##/#...#/#...#/#...#',
    O: '.###./#...#/#...#/#...#/#...#/#...#/.###.', P: '####./#...#/#...#/####./#..../#..../#....',
    Q: '.###./#...#/#...#/#...#/#.#.#/#..#./.##.#', R: '####./#...#/#...#/####./#.#../#..#./#...#',
    S: '.####/#..../#..../.###./....#/....#/####.', T: '#####/..#../..#../..#../..#../..#../..#..',
    U: '#...#/#...#/#...#/#...#/#...#/#...#/.###.', V: '#...#/#...#/#...#/#...#/#...#/.#.#./..#..',
    W: '#...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#', X: '#...#/#...#/.#.#./..#../.#.#./#...#/#...#',
    Y: '#...#/#...#/.#.#./..#../..#../..#../..#..', Z: '#####/....#/...#./..#../.#.../#..../#####',
    0: '.###./#...#/#..##/#.#.#/##..#/#...#/.###.', 1: '..#../.##../..#../..#../..#../..#../.###.',
    2: '.###./#...#/....#/...#./..#../.#.../#####', 3: '####./....#/....#/.###./....#/....#/####.',
    4: '...#./..##./.#.#./#..#./#####/...#./...#.', 5: '#####/#..../####./....#/....#/#...#/.###.',
    6: '..##./.#.../#..../####./#...#/#...#/.###.', 7: '#####/....#/...#./..#../.#.../.#.../.#...',
    8: '.###./#...#/#...#/.###./#...#/#...#/.###.', 9: '.###./#...#/#...#/.####/....#/...#./.##..',
    '.': '...../...../...../...../...../.##../.##..', ',': '...../...../...../...../.##../..#../.#...',
    '!': '..#../..#../..#../..#../..#../...../..#..', '?': '.###./#...#/....#/...#./..#../...../..#..',
    "'": '..#../..#../.#.../...../...../...../.....', '"': '.#.#./.#.#./...../...../...../...../.....',
    ':': '...../.##../.##../...../.##../.##../.....', '-': '...../...../...../#####/...../...../.....',
    '+': '...../..#../..#../#####/..#../..#../.....', '/': '....#/....#/...#./..#../.#.../#..../#....',
    '(': '...#./..#../.#.../.#.../.#.../..#../...#.', ')': '.#.../..#../...#./...#./...#./..#../.#...',
    '>': '#..../.#.../..#../...#./..#../.#.../#....', '<': '....#/...#./..#../.#.../..#../...#./....#',
    '%': '##..#/##..#/...#./..#../.#.../#..##/#..##', '_': '...../...../...../...../...../...../#####',
    // Three dots at mid height, for the thinking bubble.
    '^': '...../...../...../#.#.#/...../...../.....',
    // A solid block, for the typing cursor.
    '`': '#####/#####/#####/#####/#####/#####/#####',
  };
  const FONT = {};
  for (const [letter, source] of Object.entries(FONT_SOURCE)) {
    const rows = source.split('/');
    if (rows.length !== 7 || rows.some((row) => row.length !== 5)) throw new Error(`Font glyph ${letter} is not 5 by 7`);
    FONT[letter] = rows;
  }

  // One glyph as a sprite in one colour, for the marks inside Finn's bubble.
  function glyphSprite(letter, colour = 'K') {
    return makeSprite(`glyph ${letter}`, FONT[letter].map((row) => row.replace(/#/g, colour)), false);
  }

  function text(ctx, string, x, y, colour = P.white, scale = 1) {
    ctx.fillStyle = colour;
    let cursor = Math.round(x);
    for (const letter of String(string).toUpperCase()) {
      const glyph = FONT[letter];
      if (glyph) {
        for (let r = 0; r < 7; r++) {
          for (let c = 0; c < 5; c++) {
            if (glyph[r][c] === '#') ctx.fillRect(cursor + c * scale, Math.round(y) + r * scale, scale, scale);
          }
        }
      }
      cursor += 6 * scale;
    }
  }

  // ---------------------------------------------------------------- moods

  // The app's twelve moods (FishMood in App/UI/FishView.swift), in the order of the sprite sheet.
  // icon: a letter in the status bubble, ' ' for an empty bubble, '*' for sparkles, '~' for a popping memory.
  const MOODS = {
    happy: { eye: 'normal', mouth: 'smile', icon: null, label: 'HAPPY' },
    curious: { eye: 'wide', mouth: 'open', icon: '!', label: 'CURIOUS' },
    listening: { eye: 'down', mouth: 'smile', icon: null, label: 'LISTENING' },
    thinking: { eye: 'up', mouth: 'flat', icon: '^', label: 'THINKING' },
    proud: { eye: 'happy', mouth: 'open', icon: '*', label: 'PROUD' },
    confused: { eye: 'small', mouth: 'flat', icon: '?', label: 'CONFUSED' },
    shrug: { eye: 'up', mouth: 'open', icon: ' ', label: 'NOT TAUGHT' },
    forgetful: { eye: 'half', mouth: 'open', icon: '~', label: 'FORGETFUL' },
    inspecting: { eye: 'down', mouth: 'flat', icon: null, lens: true, label: 'INSPECTING' },
    graduate: { eye: 'happy', mouth: 'open', icon: '*', cap: true, label: 'GRADUATE' },
    focused: { eye: 'focus', mouth: 'flat', icon: null, headband: true, label: 'FOCUSED' },
    sleepy: { eye: 'shut', mouth: 'smile', icon: 'Z', label: 'RESTING' },
  };

  // Where the extras sit, in fish pixels from the fish's top-left corner.
  const RIG = {
    cap: [9, -3],
    lens: [17, 12],
    headband: [7, 2],
    bubble: [18, -7],
  };

  // Timing, in steps per second. FishView.swift uses the same numbers.
  const TIMING = { tail: 4, bob: 2, blinkEvery: 3.6, blinkFor: 0.18, sparkle: 4, pop: 3 };

  // The layers of one frame of Finn, as [sprite, x, y] in fish pixels. Pure, so the Swift port can mirror it.
  function fishLayers(mood = 'happy', t = 0, options = {}) {
    const look = MOODS[mood];
    const still = options.still;
    const tail = still ? 0 : Math.floor(t * TIMING.tail) % 2;
    const bob = still ? 0 : Math.floor(t * TIMING.bob) % 2;
    let eye = look.eye;
    const canBlink = eye !== 'happy' && eye !== 'shut';
    if (!still && canBlink && (t % TIMING.blinkEvery) > TIMING.blinkEvery - TIMING.blinkFor) eye = 'shut';
    const layers = [[fishSprite(tail, eye, look.mouth), 0, bob]];
    const at = (name, sprite) => layers.push([sprite || SPRITES[name], RIG[name][0], RIG[name][1] + bob]);
    if (look.headband) at('headband');
    if (look.cap) at('cap');
    if (look.lens) at('lens');
    if (options.icon === false || look.icon === null) return layers;
    const [ix, iy0] = RIG.bubble;
    const iy = iy0 + bob;
    if (look.icon === '*') {
      const beat = still ? 0 : Math.floor(t * TIMING.sparkle) % 3;
      layers.push([beat === 0 ? SPRITES.sparkle : SPRITES.spark, ix + 2, iy + 1]);
      layers.push([beat === 1 ? SPRITES.sparkle : SPRITES.spark, ix + 8, iy + 7]);
      layers.push([beat === 2 ? SPRITES.sparkle : SPRITES.spark, ix - 5, iy - 2]);
    } else if (look.icon === '~') {
      const beat = still ? 0 : Math.floor(t * TIMING.pop) % 3;
      if (beat === 0) layers.push([SPRITES.bubble, ix, iy]);
      if (beat === 1) layers.push([SPRITES.popping, ix, iy]);
    } else {
      layers.push([SPRITES.bubble, ix, iy]);
      if (look.icon !== ' ') layers.push([glyphSprite(look.icon), ix + 2, iy + 1]);
    }
    return layers;
  }

  function drawFish(ctx, x, y, t, mood = 'happy', scale = 1, options = {}) {
    for (const [sprite, dx, dy] of fishLayers(mood, t, options)) drawSprite(ctx, sprite, x + dx * scale, y + dy * scale, scale);
  }

  // The box every frame of Finn fits in, in fish pixels: from (0, -9), 31 wide and 31 tall, bob included.
  // The room above and to the right is for the bubble and sparkles. the sprite generator checks it.
  const FRAME = { x: 0, y: -9, w: 31, h: 31 };

  // ---------------------------------------------------------------- Orla, the tutor

  // Orla is a red-cap Oranda: a white goldfish whose bumpy red hood looks like a brain.
  // She wears the round glasses the first Finn had. 26 by 18, facing right like Finn.
  const ORLA_ROWS = [
    '..............X.X.X.......',
    '..........C..XrXrXXX......',
    '.........CW.XXXrXXXXX.....',
    '........CWWXXXXXXrXXXX....',
    '.CC....CWWWWDXXXXXXXXXX...',
    'CWWC..CWWWWWWDDXXXXXXXXD..',
    'CWWWC.WWWWWWWWWXKKKKXXXD..',
    '.CWWWCWWWWWWWWKWWWWWWKWWW.',
    '..CWWWWWWWWKKKKWWWWWWKKWWW',
    '..CWWWWWWWWWWWKWWWWWWKWWrW',
    '.CWWWCWWWWWWWWKWWWWWWKWWWM',
    'CWWWC.WWWWWWWWWWKKKKWWWWM.',
    'CWWC..CWWWWWWWWWWWWWWWWW..',
    '.CC....CWWWWWWWWWWWWWWC...',
    '........CCWWWWCCWWWWCC....',
    '..........C..CWWC.........',
    '.............CWC..........',
    '..............C...........',
  ];

  // Her second tail frame: columns 0 to 5 of rows 4 to 13. The veil tail sweeps up.
  const ORLA_TAIL_B = [
    'CC....',
    'CWWC..',
    '.CWWC.',
    '..CWWC',
    '..CWWW',
    '..CWWW',
    '.CWWWC',
    'CWWC..',
    'CWC...',
    '.C....',
  ];

  // Her eye is the lens of her glasses: a 6 by 4 patch at column 15, row 7.
  const ORLA_EYES = {
    normal: ['WWWWWW', 'WWWBBW', 'WWWBBW', 'WWWWWW'],
    up: ['WWWBBW', 'WWWBBW', 'WWWWWW', 'WWWWWW'],
    happy: ['WWWWWW', 'WKKKKW', 'KWWWWK', 'WWWWWW'],
    shut: ['WWWWWW', 'WWWWWW', 'KKKKKK', 'WWWWWW'],
  };

  const orlaCache = {};
  function orlaSprite(tail, eye) {
    const key = `${tail}-${eye}`;
    if (orlaCache[key]) return orlaCache[key];
    const rows = ORLA_ROWS.map((row) => row.split(''));
    if (tail) {
      for (let i = 0; i < ORLA_TAIL_B.length; i++) {
        for (let x = 0; x < 6; x++) rows[4 + i][x] = ORLA_TAIL_B[i][x];
      }
    }
    const patch = ORLA_EYES[eye];
    for (let r = 0; r < 4; r++) {
      for (let c = 0; c < 6; c++) rows[7 + r][15 + c] = patch[r][c];
    }
    orlaCache[key] = makeSprite(`orla ${key}`, rows.map((row) => row.join('')));
    return orlaCache[key];
  }

  // Her moods (OrlaMood in App/UI/OrlaView.swift). icon works as for Finn, plus 'bulb' for a hint.
  const ORLA_MOODS = {
    calm: { eye: 'normal', icon: null, label: 'CALM' },
    thinking: { eye: 'up', icon: '^', label: 'THINKING' },
    asking: { eye: 'normal', icon: '?', label: 'ASKING' },
    hinting: { eye: 'normal', icon: 'bulb', label: 'HINTING' },
    pleased: { eye: 'happy', icon: '*', label: 'PLEASED' },
  };
  const ORLA_RIG = { bubble: [20, -8] };
  // She moves a little slower than Finn and blinks out of step with him.
  const ORLA_TIMING = { tail: 3, blinkEvery: 4.2, blinkOffset: 1.7 };

  function orlaLayers(mood = 'calm', t = 0, options = {}) {
    const look = ORLA_MOODS[mood];
    const still = options.still;
    const tail = still ? 0 : Math.floor(t * ORLA_TIMING.tail) % 2;
    const bob = still ? 0 : Math.floor(t * TIMING.bob) % 2;
    let eye = look.eye;
    if (!still && eye !== 'happy' && ((t + ORLA_TIMING.blinkOffset) % ORLA_TIMING.blinkEvery) > ORLA_TIMING.blinkEvery - TIMING.blinkFor) eye = 'shut';
    const layers = [[orlaSprite(tail, eye), 0, bob]];
    if (options.icon === false || look.icon === null) return layers;
    const [ix, iy0] = ORLA_RIG.bubble;
    const iy = iy0 + bob;
    if (look.icon === '*') {
      const beat = still ? 0 : Math.floor(t * TIMING.sparkle) % 3;
      layers.push([beat === 0 ? SPRITES.sparkle : SPRITES.spark, ix + 2, iy + 1]);
      layers.push([beat === 1 ? SPRITES.sparkle : SPRITES.spark, ix + 7, iy + 7]);
      layers.push([beat === 2 ? SPRITES.sparkle : SPRITES.spark, ix - 5, iy - 1]);
    } else {
      layers.push([SPRITES.bubble, ix, iy]);
      if (look.icon === 'bulb') layers.push([SPRITES.bulb, ix + 2, iy + 1]);
      else layers.push([glyphSprite(look.icon), ix + 2, iy + 1]);
    }
    return layers;
  }

  function drawOrla(ctx, x, y, t, mood = 'calm', scale = 1, options = {}) {
    for (const [sprite, dx, dy] of orlaLayers(mood, t, options)) drawSprite(ctx, sprite, x + dx * scale, y + dy * scale, scale);
  }

  // Orla's frame box, like FRAME for Finn. the sprite generator checks it.
  const ORLA_FRAME = { x: -1, y: -9, w: 33, h: 29 };

  // ---------------------------------------------------------------- the fire

  // The forgiving streak's fire. Two flicker frames, embers after a missed day, and a cold log when it is out.
  const FIRE = {
    lit: [
      makeSprite('fire 0', [
        '....X....',
        '...XO....',
        '...XOX...',
        '..XOOX.X.',
        '.XOLOOXX.',
        '.XOLLOOX.',
        'XOLYYLOOX',
        'XOLYWYLOX',
        'XOLYWYLOX',
        '.XOLYLOX.',
        '..QQQQQ..',
      ]),
      makeSprite('fire 1', [
        '....X....',
        '....OX...',
        '...XOX...',
        '.X.XOOX..',
        '.XXOOLOX.',
        '.XOOLLOX.',
        'XOOLYYLOX',
        'XOLYWYLOX',
        'XOLYWYLOX',
        '.XOLYLOX.',
        '..QQQQQ..',
      ]),
    ],
    embers: makeSprite('embers', [
      '.........',
      '.........',
      '.........',
      '.........',
      '.........',
      '....X....',
      '...XOX...',
      '..XOLOX..',
      '.XDOLODX.',
      '.DXOXOXD.',
      '..QQQQQ..',
    ]),
    out: makeSprite('out', [
      '....G....',
      '...G.....',
      '....G....',
      '.....G...',
      '....G....',
      '.........',
      '.........',
      '.........',
      '.........',
      '..SSSSS..',
      '..QQQQQ..',
    ]),
  };

  // ---------------------------------------------------------------- the tank

  // Water with a moving surface, a sand floor, weeds and bubbles. FishView.swift's PixelTank mirrors it.
  function tank(ctx, x, y, w, h, t, options = {}) {
    const rect = (rx, ry, rw, rh, colour) => {
      ctx.fillStyle = colour;
      ctx.fillRect(Math.round(rx), Math.round(ry), Math.round(rw), Math.round(rh));
    };
    ctx.save();
    ctx.beginPath();
    ctx.rect(x, y, w, h);
    ctx.clip();
    const first = Math.round(h * 0.36);
    const second = Math.round(h * 0.7);
    rect(x, y, w, h, P.deep);
    rect(x, y, w, first, P.water);
    rect(x, y + first, w, second - first, P.sea);
    for (let i = 0; i < w; i += 2) {
      rect(x + i, y + first - 1, 1, 1, P.sea);
      rect(x + i + 1, y + first, 1, 1, P.water);
      rect(x + i, y + second - 1, 1, 1, P.deep);
      rect(x + i + 1, y + second, 1, 1, P.sea);
    }
    if (options.surface) {
      const shift = Math.floor(t * 3);
      for (let i = 0; i < w; i++) {
        const crest = ((i + shift) % 8) < 4;
        if (!crest) rect(x + i, y, 1, 1, options.sky || P.ink);
        rect(x + i, y + (crest ? 0 : 1), 1, 1, P.white);
        rect(x + i, y + (crest ? 1 : 2), 1, 1, P.aqua);
      }
    }
    if (options.sand !== false) {
      rect(x, y + h - 6, w, 6, P.cream);
      for (let i = 0; i < w; i += 5) rect(x + i, y + h - 7, 2, 1, P.cream);
      for (let i = 0; i < 12; i++) rect(x + ((i * 23 + 7) % w), y + h - 4 + (i % 2) * 2, 1, 1, P.sand);
    }
    (options.weeds || []).forEach((offset, index) => {
      drawSprite(ctx, SPRITES.weed, x + offset, y + h - 20, 1, Math.floor(t * 1.5 + index) % 2 === 1);
    });
    const count = options.bubbles === undefined ? 4 : options.bubbles;
    for (let i = 0; i < count; i++) {
      const period = 5 + i * 1.3;
      const progress = ((t + i * 2.1) / period) % 1;
      const bx = x + 3 + ((i * 37 + 17) % (w - 12)) + Math.round(Math.sin(t * 2 + i));
      const by = y + h - 10 - progress * (h - 16);
      drawSprite(ctx, i % 2 ? SPRITES.ring3 : SPRITES.ring5, bx, Math.round(by));
    }
    ctx.restore();
  }

  return {
    P, KEY, makeSprite, drawSprite, fishSprite, glyphSprite, FISH_ROWS, TAIL_B, EYES, MOUTHS, SPRITES, FONT, text,
    MOODS, RIG, TIMING, FRAME, fishLayers, drawFish, tank,
    ORLA_ROWS, ORLA_TAIL_B, ORLA_EYES, ORLA_MOODS, ORLA_RIG, ORLA_TIMING, ORLA_FRAME, orlaSprite, orlaLayers, drawOrla,
    FIRE,
  };
});

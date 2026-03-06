const text = "Lorem ipsum dolor si<103>amet, consectetur adip<100>cing<101>lit. Susp<102>d<100>se h<102>dreri<103>justo<101>lem<102>tum tr<100>tique pharetra. Susp<102>d<100>se vehicula a<103>maur<100><101>u facil<100><100>. Nunc<101>s<103>es<103>libero.\n"
const dic = `(p, e) => 0
	 (s,  ) => 0
	 (e, r) => 2
	 (s, s) => 0
	 (c, t) => 1
	 (i, c) => 1
	 (e, h) => 1
	 (a, 103) => 1
	 (r, o) => 1
	 ( , l) => 0
	 (g,  ) => 0
	 (a,  ) => 1
	 (u, s) => 3
	 (103, a) => 1
	 (n, g) => 1
	 (u, l) => 1
	 (S, u) => 2
	 (e, s) => 0
	 (l, i) => 2
	 (h, 102) => 1
	 (u, e) => 1
	 (l, a) => 1
	 (i, 103) => 2
	 (L, o) => 1
	 (u, n) => 1
	 (f, a) => 1
	 (s, 103) => 1
	 (e,  ) => 3
	 (p, i) => 0
	 (100, 101) => 1
	 (t, .) => 1
	 (s, t) => 2
	 (m, a) => 1
	 (e, l) => 0
	 (s, .) => 0
	 ( , t) => 1
	 (a, c) => 1
	 ( , f) => 1
	 (100, 100) => 1
	 (u, m) => 2
	 ( , N) => 1
	 (e, t) => 3
	 ( , j) => 0
	 ( , m) => 0
	 (100, s) => 2
	 (v, e) => 1
	 (t, o) => 1
	 ( , v) => 1
	 ( , e) => 0
	 (c, o) => 1
	 (o, 101) => 1
	 (o, r) => 2
	 (n, d) => 0
	 (h, e) => 0
	 (103, j) => 1
	 (p, s) => 1
	 (100, i) => 0
	 (u,  ) => 1
	 (o, .) => 1
	 (m, e) => 1
	 (r, 100) => 2
	 (i, l) => 1
	 (r, e) => 3
	 (100, c) => 1
	 ( , c) => 1
	 ( , d) => 1
	 (e, m) => 2
	 (s, p) => 2
	 (p, h) => 1
	 (e, c) => 1
	 (s, i) => 1
	 ( , h) => 1
	 (t, e) => 1
	 (101, s) => 2
	 (s, c) => 0
	 (o, l) => 1
	 (t, ,) => 1
	 (i, n) => 1
	 (h, i) => 1
	 (,,  ) => 1
	 (t, r) => 2
	 (c,  ) => 0
	 (a, m) => 1
	 (q, u) => 1
	 (e, u) => 0
	 ( , s) => 1
	 (p, 100) => 1
	 ( , p) => 1
	 (d, 100) => 2
	 (103, l) => 1
	 (.,  ) => 3
	 (e, n) => 0
	 ( , a) => 2
	 (102, d) => 3
	 (l, e) => 1
	 (i, t) => 1
	 (a, .) => 1
	 (100, t) => 1
	 (a, r) => 1
	 (i, q) => 1
	 (m, 102) => 1
	 (h, a) => 1
	 (m,  ) => 3
	 (a, d) => 1
	 (100, .) => 1
	 (i, p) => 2
	 (a, t) => 0
	 (b, e) => 1
	 (t, u) => 2
	 (t,  ) => 0
	 (s, u) => 1
	 (102, t) => 1
	 (d, i) => 1
	 (N, u) => 1
	 (.,
) => 1
	 (n, c) => 1
	 (t, i) => 1
	 ( , S) => 2
	 (101, u) => 1
	 ( , i) => 1
	 (g, 101) => 1
	 (103, m) => 1
	 (s, e) => 3
	 (p, 102) => 2
	 (n, t) => 0
	 (i, b) => 1
	 (a, u) => 1
	 (d, o) => 1
	 (l, 100) => 1
	 (c, u) => 1
	 (n, s) => 1
	 (o,  ) => 0
	 (c, i) => 2
	 (o, n) => 1
	 (r, i) => 1
	 (c, 101) => 1
	 (j, u) => 1
	 (i, s) => 0
	 (r,  ) => 2
	 (d, r) => 1
	 (r, a) => 1
	 (t, 101) => 1
	 (100,  ) => 0
	 (l, o) => 1
	 (101, l) => 2
	 (u, r) => 2`

const Separator = "asdkfjalksdhf3i047523489572894*&*(&(#QOJHDSKAUGHDIU"


function parseText() {
    let i = 0;
    function getChar() {
        if (text[i] === "<") {
            const spike = text.slice(i).indexOf(">") + 1;
            const ret = text.slice(i, i + spike);
            i += spike
            return ret;
        }

        return text[i++]
    }


    const map = new Map();
    let l = getChar();
    while (i < text.length) {
        let r = getChar();
        const key = `${l}${Separator}${r}`;

        if (map.has(key)) {
            map.set(key, map.get(key) + 1);
        } else {
            map.set(key, 1);
        }

        l = r;
    }

    // for (const [k, v] of map) {
    //     const [a, b] = k.split(Separator);
    //     console.log(`(${a[0] == '<' ? a.slice(1, a.length - 1) : a}, ${b[0] == '<' ? b.slice(1, b.length - 1) : b}) => ${v}`);
    // }
    //
    return map;
}

function parsePair() {
    let dicIndex = 0;

    const map = new Map();

    function getPair() {
        let beginIndex = dic.indexOf('(', dicIndex);

        const closeParen = dic.indexOf(')', dicIndex);
        let endIndex = dic.indexOf('\n', closeParen);
        if (endIndex === -1) endIndex = dic.length;

        const pair = dic.slice(beginIndex, endIndex);
        dicIndex = endIndex + 1;

        return pair.trim();
    }

    function normalize(v) {
        if (v.length > 1) return "<" + v + ">";
        return v;
    }

    function addPair(line) {
        if (!line) return;

        const inside = line.slice(1, line.indexOf(')'));
        let commaIndex = inside.indexOf(',', 1);

        let l = inside.slice(0, commaIndex);
        let r = inside.slice(commaIndex + 1);

        const lNorm = normalize(l)
        const rNorm = normalize(r[0] == ' ' ? r.slice(1) : r);

        const count = parseInt(line.split('=>')[1].trim(), 10);

        const key = `${lNorm}${Separator}${rNorm}`;
        map.set(key, count);
    }

    while (dicIndex < dic.length) {
        addPair(getPair());
    }

    return map;
}


const dicMap = parsePair();
const textMap = parseText();

function diffMaps(a, b) {
    const keys = new Set([...a.keys(), ...b.keys()]);

    for (const k of keys) {
        const av = a.get(k) ?? 0;
        const bv = b.get(k) ?? 0;

        // ignore if both are zero
        if (av === 0 && bv === 0) continue;

        if (av !== bv) {
            const [l, r] = k.split(Separator);

            console.log(
                `(${l}, ${r}) => text:${av} dic:${bv}`
            );
        }
    }
}

diffMaps(textMap, dicMap);

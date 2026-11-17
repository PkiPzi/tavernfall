// Decompressors for Baldur's Gate 3 data, built by gr2.py into libcodecs.so.
// BitKnit2 (Granny .gr2 sections) is written from the public description of the format:
// eiz/libbg3 docs/bitknit2.txt and Fabian Giesen's rANS / BitKnit articles.
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define TOTAL 32768  // 15 frequency bits
#define INTERVAL 1024
#define MAXV 300

typedef struct {
  int vocab;
  uint16_t sums[MAXV + 1], acc[MAXV];
  uint16_t lookup[1024];
  int counter;
} Model;

static void model_lookup(Model* m) {
  uint32_t code = 0, sym = 0, next = m->sums[1];
  while (code < TOTAL) {
    if (code < next) { m->lookup[code >> 5] = sym; code += 32; }
    else { sym++; next = m->sums[sym + 1]; }
  }
}

static void model_init(Model* m, int vocab, int min_probable) {
  int equi = vocab - min_probable;
  m->vocab = vocab;
  m->counter = 0;
  for (int i = 0; i < equi; i++) m->sums[i] = (uint32_t)(TOTAL - min_probable) * i / equi;
  for (int i = equi; i <= vocab; i++) m->sums[i] = TOTAL - vocab + i;
  for (int i = 0; i < vocab; i++) m->acc[i] = 1;
  model_lookup(m);
}

static void model_observe(Model* m, uint32_t sym) {
  int incr = (TOTAL - m->vocab) / INTERVAL;
  m->acc[sym] += incr;
  m->counter = (m->counter + 1) % INTERVAL;
  if (m->counter) return;
  m->acc[sym] += 1 + TOTAL - m->vocab - incr * INTERVAL;
  int32_t sum = 0;
  for (int i = 1; i <= m->vocab; i++) {
    sum += m->acc[i - 1];
    m->sums[i] += (sum - (int32_t)m->sums[i]) >> 1;  // floor, also when negative
    m->acc[i - 1] = 1;
  }
  model_lookup(m);
}

typedef struct {
  const uint16_t *cur, *end;
  uint32_t s1, s2;  // two interleaved rANS states, swapped after every symbol
  int err;
} In;

static uint32_t word(In* in) {
  if (in->cur == in->end) { in->err = 1; return 0; }
  return *in->cur++;
}

static uint32_t refill(In* in, uint32_t bits) {
  return bits < 0x10000 ? (bits << 16) | word(in) : bits;
}

static uint32_t pop_bits(In* in, int n) {
  uint32_t sym = in->s1 & ((1u << n) - 1);
  uint32_t rest = refill(in, in->s1 >> n);
  in->s1 = in->s2;
  in->s2 = rest;
  return sym;
}

static uint32_t pop_model(In* in, Model* m) {
  uint32_t code = in->s1 & (TOTAL - 1);
  uint32_t sym = m->lookup[code >> 5];
  while (code >= m->sums[sym + 1]) sym++;
  uint32_t rest = refill(in, (in->s1 >> 15) * (m->sums[sym + 1] - m->sums[sym]) + code - m->sums[sym]);
  in->s1 = in->s2;
  in->s2 = rest;
  model_observe(m, sym);
  return sym;
}

// Returns 0 on success. src_len is in bytes.
int bitknit2_decode(const uint16_t* src, size_t src_len, uint8_t* dst, size_t dst_len) {
  static Model command[4], cache_ref[4], offset_model;  // shortcut: not thread safe, make them locals if ever threaded
  In in = {src, src + src_len / 2, 0, 0, 0};
  uint32_t cache[8], order = 0x76543210;
  size_t pos = 0, delta = 1;
  for (int i = 0; i < 4; i++) { model_init(&command[i], 300, 36); model_init(&cache_ref[i], 40, 0); }
  model_init(&offset_model, 21, 0);
  for (int i = 0; i < 8; i++) cache[i] = 1;
  if (word(&in) != 0x75B1) return 1;

  while (pos < dst_len) {
    if (in.cur == in.end) return 2;
    size_t quantum_end = (pos & ~(size_t)0xFFFF) + 0x10000;
    if (quantum_end > dst_len) quantum_end = dst_len;
    if (*in.cur == 0) {  // raw quantum
      in.cur++;
      size_t n = (size_t)(in.end - in.cur) * 2;
      if (n > quantum_end - pos) n = quantum_end - pos;
      memcpy(dst + pos, in.cur, n);
      pos += n;
      in.cur += n / 2;
      continue;
    }
    // the two states are stored merged at the start of each quantum
    uint32_t merged = word(&in) << 16;
    merged |= word(&in);
    uint32_t split = merged & 15;
    merged = refill(&in, merged >> 4);
    in.s1 = refill(&in, merged >> split);
    in.s2 = ((merged << 16) | word(&in)) & ((1u << (16 + split)) - 1);
    in.s2 |= 1u << (16 + split);

    if (pos == 0) dst[pos++] = pop_bits(&in, 8);
    while (pos < quantum_end) {
      if (in.err) return 3;
      uint32_t cmd = pop_model(&in, &command[pos % 4]);
      if (cmd < 256) {
        dst[pos] = cmd + dst[pos - delta];
        pos++;
        continue;
      }
      int mi = pos % 4;
      uint32_t len;
      if (cmd < 288) len = cmd - 254;
      else { int n = cmd - 287; len = (1u << n) + pop_bits(&in, n) + 32; }
      uint32_t off, ref = pop_model(&in, &cache_ref[mi]);
      if (ref < 8) {
        uint32_t slot = (order >> (ref * 4)) & 15;
        uint32_t mask = (16u << (ref * 4)) - 1;
        order = (order & ~mask) | (((order << 4) | slot) & mask);
        off = cache[slot];
      } else {
        uint32_t n = pop_model(&in, &offset_model);
        uint32_t bits = pop_bits(&in, n % 16);
        if (n >= 16) bits = (bits << 16) | word(&in);
        off = (32u << n) + (bits << 5) - 32 + (ref - 7);
        cache[order >> 28] = cache[(order >> 24) & 15];
        cache[(order >> 24) & 15] = off;
      }
      if (off > pos || len > dst_len - pos) return 4;
      delta = off;
      for (uint32_t i = 0; i < len; i++, pos++) dst[pos] = dst[pos - off];
    }
    if (in.err || in.s1 != 0x10000 || in.s2 != 0x10000) return 5;
  }
  return 0;
}


// FastLZ (levels 1 and 2), used by BG3's virtual texture tiles. Returns bytes written, or -1.
long fastlz_decode(const uint8_t* ip, size_t in_len, uint8_t* out, size_t out_len) {
  const uint8_t* end = ip + in_len;
  uint8_t *op = out, *op_end = out + out_len;
  if (!in_len) return 0;
  int level2 = (*ip >> 5) == 1;
  uint32_t ctrl = *ip++ & 31;
  for (;;) {
    if (ctrl >= 32) {
      uint32_t len = (ctrl >> 5) - 1, ofs = (ctrl & 31) << 8;
      if (len == 6) {
        if (level2) { uint8_t c; do { if (ip >= end) return -1; c = *ip++; len += c; } while (c == 255); }
        else { if (ip >= end) return -1; len += *ip++; }
      }
      if (ip >= end) return -1;
      uint8_t low = *ip++;
      ofs += low;
      if (level2 && low == 255 && (ctrl & 31) == 31) {
        if (ip + 2 > end) return -1;
        ofs = ((uint32_t)ip[0] << 8) + ip[1] + 8191;
        ip += 2;
      }
      len += 3;
      if (ofs + 1 > (size_t)(op - out) || len > (size_t)(op_end - op)) return -1;
      for (const uint8_t* ref = op - ofs - 1; len; len--) *op++ = *ref++;
    } else {
      ctrl++;
      if (ctrl > (size_t)(end - ip) || ctrl > (size_t)(op_end - op)) return -1;
      memcpy(op, ip, ctrl);
      op += ctrl;
      ip += ctrl;
    }
    if (ip >= end) break;
    ctrl = *ip++;
  }
  return op - out;
}

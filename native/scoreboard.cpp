// scoreboard -- the native rendition of the harness's measurement path.
//
// This is C++ because C++ is the one native rendition of the transpiler's five targets that
// is recorded as having actually run on this host (reports/languages.json, `g++ 16.2.1`,
// status `ran`). There is no C emitter, so a C rendition of the algorithm does not exist and
// this file does not pretend to be one. What it is: the harness's scoring and content
// addressing, written natively so the same work can be timed against the TypeScript path.
//
// Three jobs, and they are deliberately separable:
//
//   --digest <text>   SHA-256 of the text, first 16 hex characters. This mirrors
//                     `src/util.ts: sha256()` exactly -- same algorithm, same truncation --
//                     so `--selftest` and `verify.ts` can hold the two renditions to
//                     byte-identical output. That equality is the accuracy claim.
//   --sum [file]      read a TSV of per-rendition measurements and print the scoreboard.
//   --selftest        check the digest against published vectors, and stop.
//
//     g++ -std=c++20 -O2 -o out/scoreboard native/scoreboard.cpp
//     ./out/scoreboard --selftest
//     ./out/scoreboard --sum reports/versions.tsv

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

// ---------------------------------------------------------------- SHA-256

const std::uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
    0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
    0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
    0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
    0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
    0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
    0xc67178f2u};

inline std::uint32_t rotr(std::uint32_t x, std::uint32_t n) {
  return (x >> n) | (x << (32u - n));
}

std::string sha256(std::string const& message) {
  std::vector<std::uint8_t> data(message.begin(), message.end());
  const std::uint64_t bitLength = static_cast<std::uint64_t>(data.size()) * 8u;

  data.push_back(0x80u);
  while (data.size() % 64u != 56u) data.push_back(0x00u);
  for (int shift = 7; shift >= 0; --shift) {
    data.push_back(static_cast<std::uint8_t>((bitLength >> (8 * shift)) & 0xffu));
  }

  std::uint32_t h[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                        0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

  for (std::size_t offset = 0; offset < data.size(); offset += 64u) {
    std::uint32_t w[64];
    for (int i = 0; i < 16; ++i) {
      const std::size_t at = offset + static_cast<std::size_t>(4 * i);
      w[i] = (static_cast<std::uint32_t>(data[at]) << 24) |
             (static_cast<std::uint32_t>(data[at + 1]) << 16) |
             (static_cast<std::uint32_t>(data[at + 2]) << 8) |
             static_cast<std::uint32_t>(data[at + 3]);
    }
    for (int i = 16; i < 64; ++i) {
      const std::uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      const std::uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    std::uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    std::uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

    for (int i = 0; i < 64; ++i) {
      const std::uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const std::uint32_t ch = (e & f) ^ ((~e) & g);
      const std::uint32_t temp1 = hh + S1 + ch + K[i] + w[i];
      const std::uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const std::uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
      const std::uint32_t temp2 = S0 + maj;
      hh = g; g = f; f = e; e = d + temp1;
      d = c; c = b; b = a; a = temp1 + temp2;
    }

    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }

  std::ostringstream out;
  for (std::uint32_t word : h) {
    out << std::hex << std::setw(8) << std::setfill('0') << word;
  }
  return out.str().substr(0, 16);  // src/util.ts slices to 16
}

}  // namespace

// ---------------------------------------------------------------- the scoreboard

namespace {

struct Row {
  std::string id;
  std::string kind;
  double accuracy = 0.0;
  double ms = 0.0;
  std::string note;
};

/** Split on tabs. A line with fewer than four fields is malformed and is reported, not guessed. */
bool parseRow(std::string const& line, Row& row) {
  std::vector<std::string> field;
  std::string current;
  std::istringstream stream(line);
  while (std::getline(stream, current, '\t')) field.push_back(current);
  if (field.size() < 4) return false;
  row.id = field[0];
  row.kind = field[1];
  try {
    row.accuracy = std::stod(field[2]);
    row.ms = std::stod(field[3]);
  } catch (...) {
    return false;
  }
  row.note = field.size() > 4 ? field[4] : "";
  return true;
}

std::string fixed(double value, int places) {
  std::ostringstream out;
  out << std::fixed << std::setprecision(places) << value;
  return out.str();
}

std::string pad(std::string const& text, std::size_t width) {
  if (text.size() >= width) return text;
  return text + std::string(width - text.size(), ' ');
}

int readRows(std::istream& in, std::vector<Row>& rows, std::vector<std::string>& rejected) {
  std::string line;
  while (std::getline(in, line)) {
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.pop_back();
    if (line.empty() || line[0] == '#') continue;
    Row row;
    if (parseRow(line, row)) {
      rows.push_back(row);
    } else {
      rejected.push_back(line);
    }
  }
  return static_cast<int>(rows.size());
}

}  // namespace

int main(int argc, char** argv) {
  const std::vector<std::string> args(argv + 1, argv + argc);

  if (args.empty() || args[0] == "--help" || args[0] == "-h") {
    std::cout << "scoreboard --digest <text> | --sum [file] | --selftest | --bench-digest <n> [bytes]\n"
              << "  --digest        SHA-256, first 16 hex characters, byte-identical to src/util.ts\n"
              << "  --sum           score a TSV of: id<TAB>kind<TAB>accuracy<TAB>ms<TAB>note\n"
              << "  --selftest      check the digest against published vectors\n"
              << "  --bench-digest  time `n` digests of one `bytes`-byte document\n";
    return 0;
  }

  if (args[0] == "--digest") {
    const std::string text = args.size() > 1 ? args[1] : "";
    std::cout << sha256(text) << "\n";
    return 0;
  }

  if (args[0] == "--selftest") {
    // Published NIST vectors, sliced to 16 characters as src/util.ts does.
    struct Vector { const char* input; const char* expected; };
    const Vector vectors[] = {
        {"", "e3b0c44298fc1c14"},
        {"abc", "ba7816bf8f01cfea"},
        {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8"},
    };
    int failures = 0;
    for (Vector const& vector : vectors) {
      const std::string got = sha256(vector.input);
      const bool ok = got == vector.expected;
      if (!ok) ++failures;
      std::cout << (ok ? "ok   " : "FAIL ") << "\"" << std::string(vector.input).substr(0, 24)
                << (std::string(vector.input).size() > 24 ? "..." : "") << "\" -> " << got
                << (ok ? "" : std::string(" expected ") + vector.expected) << "\n";
    }
    std::cout << "vectors " << (sizeof(vectors) / sizeof(vectors[0])) << " · failures " << failures
              << "\n";
    return failures == 0 ? 0 : 1;
  }

  if (args[0] == "--sum") {
    std::vector<Row> rows;
    std::vector<std::string> rejected;
    const auto started = std::chrono::steady_clock::now();

    if (args.size() > 1 && args[1] != "-") {
      std::ifstream file(args[1]);
      if (!file) {
        std::cerr << "cannot read " << args[1] << "\n";
        return 2;
      }
      readRows(file, rows, rejected);
    } else {
      readRows(std::cin, rows, rejected);
    }

    if (rows.empty()) {
      std::cerr << "no rows\n";
      return 2;
    }

    const Row* fastest = nullptr;
    const Row* slowest = nullptr;
    double totalMs = 0.0;
    double totalAccuracy = 0.0;
    for (Row const& row : rows) {
      totalMs += row.ms;
      totalAccuracy += row.accuracy;
      // A rendition that produced nothing has a real timing -- how long its toolchain took to
      // answer -- but ranking it as the fastest rendition would be a lie of arithmetic. It is
      // excluded from the ranking and still counted in every total above.
      if (row.accuracy <= 0.0) continue;
      if (fastest == nullptr || row.ms < fastest->ms) fastest = &row;
      if (slowest == nullptr || row.ms > slowest->ms) slowest = &row;
    }

    std::cout << pad("rendition", 22) << pad("kind", 20) << pad("accuracy", 10) << "ms\n";
    std::cout << std::string(22 + 20 + 10 + 10, '-') << "\n";
    for (Row const& row : rows) {
      std::cout << pad(row.id, 22) << pad(row.kind, 20) << pad(fixed(row.accuracy, 4), 10)
                << fixed(row.ms, 1) << "\n";
    }
    std::cout << "\n";
    std::cout << "renditions            " << rows.size() << "\n";
    std::cout << "mean accuracy         " << fixed(totalAccuracy / static_cast<double>(rows.size()), 4) << "\n";
    std::cout << "total ms              " << fixed(totalMs, 1) << "\n";
    if (fastest != nullptr && slowest != nullptr) {
      std::cout << "fastest that ran      " << fastest->id << " (" << fixed(fastest->ms, 1) << " ms)\n";
      std::cout << "slowest that ran      " << slowest->id << " (" << fixed(slowest->ms, 1) << " ms)\n";
    } else {
      std::cout << "fastest that ran      none -- no rendition produced output\n";
    }

    if (!rejected.empty()) {
      std::cout << "malformed lines       " << rejected.size() << "\n";
      for (std::string const& line : rejected) std::cout << "  " << line << "\n";
    }

    if (args.size() > 2 && args[2] == "--digest") {
      // Content-addressed over the rows as read, so the same measurements produce the same id.
      std::string corpus;
      for (Row const& row : rows) {
        corpus += row.id + "\t" + row.kind + "\t" + fixed(row.accuracy, 4) + "\t" + fixed(row.ms, 1) + "\n";
      }
      std::cout << "report digest         " << sha256(corpus) << "\n";
    }

    const auto elapsed = std::chrono::duration<double, std::milli>(
                             std::chrono::steady_clock::now() - started)
                             .count();
    std::cout << "scoreboard ms         " << fixed(elapsed, 3) << "\n";
    return 0;
  }

  if (args[0] == "--bench-digest") {
    // The same work the TypeScript path does in `bin/bench-sha.mjs`, so the two timings are
    // comparable: `iterations` digests of one `sizeBytes`-byte document.
    const int iterations = args.size() > 1 ? std::stoi(args[1]) : 20000;
    const std::size_t sizeBytes = args.size() > 2 ? static_cast<std::size_t>(std::stoul(args[2])) : 4096;
    const std::string document(sizeBytes, 'x');

    const auto started = std::chrono::steady_clock::now();
    std::string last;
    for (int i = 0; i < iterations; ++i) last = sha256(document);
    const double elapsed =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();

    std::cout << "iterations            " << iterations << "\n";
    std::cout << "bytes per document    " << sizeBytes << "\n";
    std::cout << "total ms              " << fixed(elapsed, 3) << "\n";
    std::cout << "per digest us         " << fixed(elapsed * 1000.0 / iterations, 3) << "\n";
    std::cout << "digests per second    " << fixed(iterations / (elapsed / 1000.0), 1) << "\n";
    std::cout << "last digest           " << last << "\n";
    return 0;
  }

  std::cerr << "unknown option: " << args[0] << " (try --help)\n";
  return 2;
}

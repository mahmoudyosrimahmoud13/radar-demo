/// Minimal Intel HEX parser -- enough to read the .hex files the Arduino
/// IDE/CLI produces for an Uno (ATmega328P, 32KB flash, so addresses never
/// exceed 16 bits and we don't need to handle the extended-segment-address
/// record type 02, only 00 data / 01 EOF / 04 extended-linear-address).
class IntelHexParseException implements Exception {
  final String message;
  IntelHexParseException(this.message);
  @override
  String toString() => 'IntelHexParseException: $message';
}

class IntelHexResult {
  /// Sparse flash image: byte address -> value. Use [flattenToPages] to
  /// turn this into fixed-size pages for STK500 page writes.
  final Map<int, int> bytes;
  final int highestAddress;
  IntelHexResult(this.bytes, this.highestAddress);
}

class IntelHex {
  static IntelHexResult parse(String contents) {
    final bytes = <int, int>{};
    int extendedBase = 0;
    int highest = 0;

    final lines = contents.split(RegExp(r'\r?\n'));
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith(':')) {
        throw IntelHexParseException('Line does not start with ":": $line');
      }
      final data = _hexToBytes(line.substring(1));
      if (data.length < 5) {
        throw IntelHexParseException('Record too short: $line');
      }

      final byteCount = data[0];
      final address = (data[1] << 8) | data[2];
      final recordType = data[3];
      final payload = data.sublist(4, 4 + byteCount);
      final checksum = data[4 + byteCount];

      final sum = (data[0] + data[1] + data[2] + data[3] + payload.fold<int>(0, (a, b) => a + b)) & 0xFF;
      final computedChecksum = (0x100 - sum) & 0xFF;
      if (computedChecksum != checksum) {
        throw IntelHexParseException('Bad checksum on line: $line');
      }

      switch (recordType) {
        case 0x00: // data
          final base = extendedBase + address;
          for (int i = 0; i < payload.length; i++) {
            bytes[base + i] = payload[i];
            if (base + i > highest) highest = base + i;
          }
          break;
        case 0x01: // EOF
          return IntelHexResult(bytes, highest);
        case 0x04: // extended linear address
          extendedBase = ((payload[0] << 8) | payload[1]) << 16;
          break;
        case 0x02: // extended segment address (rare for AVR, handle anyway)
          extendedBase = ((payload[0] << 8) | payload[1]) << 4;
          break;
        default:
          // ignore record types we don't need (03/05 start addresses etc.)
          break;
      }
    }

    throw IntelHexParseException('No EOF record found -- file looks truncated');
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (int i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// Splits the sparse image into fixed-size pages starting at address 0,
  /// filling any gaps with 0xFF (erased-flash value) so STK500 page writes
  /// always send full pages.
  static List<List<int>> flattenToPages(IntelHexResult result, int pageSize) {
    final pageCount = (result.highestAddress ~/ pageSize) + 1;
    final pages = <List<int>>[];
    for (int p = 0; p < pageCount; p++) {
      final page = List<int>.filled(pageSize, 0xFF);
      for (int i = 0; i < pageSize; i++) {
        final addr = p * pageSize + i;
        if (result.bytes.containsKey(addr)) page[i] = result.bytes[addr]!;
      }
      pages.add(page);
    }
    return pages;
  }
}

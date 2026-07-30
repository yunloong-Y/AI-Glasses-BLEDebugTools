/// AI-Glasses-BLEDebugTools Protocol Parser Engine
///
/// 通用 BLE 协议解析引擎，支持：
/// 1. 自定义协议定义 (JSON Schema)
/// 2. 帧格式解析（Hex/ASCII 混合模式）
/// 3. 命令/响应匹配与自动解码
/// 4. 厂商协议热加载
///
/// 协议定义结构：
///   ProtocolDef
///     ├── VendorInfo         (厂商元信息)
///     ├── GattProfile        (GATT Service/Characteristic 定义)
///     ├── FrameFormat[]      (帧格式定义，支持多层嵌套)
///     ├── CommandSet[]       (命令集：opcode 映射)
///     ├── RegisterMap[]      (寄存器地址映射)
///     └── AtCommandSet[]     (AT 命令集)

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

// ============================================================
// 协议定义数据模型
// ============================================================

/// 字节序
enum Endianness { little, big }

/// 校验类型
enum ChecksumType {
  none,
  crc8,
  crc16_ibm,    // CRC-16/IBM (BES)
  crc16_ccitt,   // CRC-16/CCITT
  crc32,
  xor8,
  sum8,
  custom,
}

/// 帧字段编码类型
enum FieldEncoding { hex, ascii, utf8, uint8, uint16, uint32, bytes }

/// 帧字段定义
class FrameFieldDef {
  final String name;
  final FieldEncoding encoding;
  final int byteLength; // 固定长度(bytes), 0 表示变长
  final Endianness? endian; // 仅对多字节类型有效
  final String? lengthSource; // 引用其他字段名作为长度
  final String? description;
  final Map<int, String>? enumMap; // 值→显示名映射

  const FrameFieldDef({
    required this.name,
    required this.encoding,
    this.byteLength = 0,
    this.endian,
    this.lengthSource,
    this.description,
    this.enumMap,
  });

  factory FrameFieldDef.fromJson(Map<String, dynamic> json) {
    return FrameFieldDef(
      name: json['name'] as String,
      encoding: FieldEncoding.values.firstWhere(
        (e) => e.name == json['encoding'],
        orElse: () => FieldEncoding.hex,
      ),
      byteLength: json['byteLength'] as int? ?? 0,
      endian: json['endian'] != null
          ? Endianness.values.firstWhere((e) => e.name == json['endian'])
          : null,
      lengthSource: json['lengthSource'] as String?,
      description: json['description'] as String?,
      enumMap: json['enumMap'] != null
          ? Map<int, String>.from(json['enumMap'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'encoding': encoding.name,
        if (byteLength > 0) 'byteLength': byteLength,
        if (endian != null) 'endian': endian!.name,
        if (lengthSource != null) 'lengthSource': lengthSource,
        if (description != null) 'description': description,
        if (enumMap != null) 'enumMap': enumMap,
      };
}

/// 帧格式定义（支持多层嵌套帧）
class FrameFormatDef {
  final String name;
  final String? description;
  final int? magicByte; // 帧头魔术字(1 byte)
  final List<int>? magicBytes; // 多字节魔术字
  final List<FrameFieldDef> fields;
  final ChecksumType checksumType;
  final int checksumOffset; // 校验字段在 fields 中的索引，-1 表示末尾
  final int checksumLength; // 校验值字节数
  final int? crcPoly; // CRC 多项式
  final int? crcInit; // CRC 初始值
  final bool crcReflect; // CRC 是否反射

  const FrameFormatDef({
    required this.name,
    this.description,
    this.magicByte,
    this.magicBytes,
    required this.fields,
    this.checksumType = ChecksumType.none,
    this.checksumOffset = -1,
    this.checksumLength = 2,
    this.crcPoly,
    this.crcInit,
    this.crcReflect = true,
  });

  factory FrameFormatDef.fromJson(Map<String, dynamic> json) {
    return FrameFormatDef(
      name: json['name'] as String,
      description: json['description'] as String?,
      magicByte: json['magicByte'] as int?,
      magicBytes: json['magicBytes'] != null
          ? List<int>.from(json['magicBytes'])
          : null,
      fields: (json['fields'] as List)
          .map((f) => FrameFieldDef.fromJson(f as Map<String, dynamic>))
          .toList(),
      checksumType: ChecksumType.values.firstWhere(
        (e) => e.name == json['checksumType'],
        orElse: () => ChecksumType.none,
      ),
      checksumOffset: json['checksumOffset'] as int? ?? -1,
      checksumLength: json['checksumLength'] as int? ?? 2,
      crcPoly: json['crcPoly'] as int?,
      crcInit: json['crcInit'] as int?,
      crcReflect: json['crcReflect'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (magicByte != null) 'magicByte': magicByte,
        if (magicBytes != null) 'magicBytes': magicBytes,
        'fields': fields.map((f) => f.toJson()).toList(),
        'checksumType': checksumType.name,
        'checksumOffset': checksumOffset,
        'checksumLength': checksumLength,
        if (crcPoly != null) 'crcPoly': crcPoly,
        if (crcInit != null) 'crcInit': crcInit,
        'crcReflect': crcReflect,
      };
}

/// GATT Characteristic 定义
class GattCharDef {
  final String name;
  final String uuid;
  final String direction; // "read" | "write" | "notify" | "indicate"
  final String? description;
  final String? writePayloadFormat; // "hex" | "ascii" | "frame"
  final String? notifyPayloadFormat;

  const GattCharDef({
    required this.name,
    required this.uuid,
    required this.direction,
    this.description,
    this.writePayloadFormat,
    this.notifyPayloadFormat,
  });

  factory GattCharDef.fromJson(Map<String, dynamic> json) {
    return GattCharDef(
      name: json['name'] as String,
      uuid: json['uuid'] as String,
      direction: json['direction'] as String,
      description: json['description'] as String?,
      writePayloadFormat: json['writePayloadFormat'] as String?,
      notifyPayloadFormat: json['notifyPayloadFormat'] as String?,
    );
  }
}

/// GATT Service 定义
class GattServiceDef {
  final String name;
  final String uuid;
  final String? description;
  final List<GattCharDef> characteristics;

  const GattServiceDef({
    required this.name,
    required this.uuid,
    this.description,
    required this.characteristics,
  });

  factory GattServiceDef.fromJson(Map<String, dynamic> json) {
    return GattServiceDef(
      name: json['name'] as String,
      uuid: json['uuid'] as String,
      description: json['description'] as String?,
      characteristics: (json['characteristics'] as List)
          .map((c) => GattCharDef.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 命令定义
class CommandDef {
  final String name;
  final int opCode;
  final String direction; // "send" | "receive" | "bidirectional"
  final String? description;
  final List<String>? paramNames;
  final List<String>? paramTypes; // "uint8" | "uint16" | "uint32" | "bytes" | "string"
  final String? responseMatch; // 匹配响应的方法

  const CommandDef({
    required this.name,
    required this.opCode,
    required this.direction,
    this.description,
    this.paramNames,
    this.paramTypes,
    this.responseMatch,
  });

  factory CommandDef.fromJson(Map<String, dynamic> json) {
    return CommandDef(
      name: json['name'] as String,
      opCode: json['opCode'] as int,
      direction: json['direction'] as String? ?? 'bidirectional',
      description: json['description'] as String?,
      paramNames: json['paramNames'] != null
          ? List<String>.from(json['paramNames'])
          : null,
      paramTypes: json['paramTypes'] != null
          ? List<String>.from(json['paramTypes'])
          : null,
      responseMatch: json['responseMatch'] as String?,
    );
  }
}

/// 命令分组
class CommandGroup {
  final String name;
  final String? description;
  final int? opCodeRangeStart; // 操作码范围
  final int? opCodeRangeEnd;
  final List<CommandDef> commands;

  const CommandGroup({
    required this.name,
    this.description,
    this.opCodeRangeStart,
    this.opCodeRangeEnd,
    required this.commands,
  });
}

/// 寄存器定义
class RegisterDef {
  final int address;
  final String name;
  final int size; // 1, 2, 4 bytes
  final String access; // "r" | "w" | "rw"
  final String? description;
  final Map<int, String>? bitFields; // bit index → 描述

  const RegisterDef({
    required this.address,
    required this.name,
    this.size = 4,
    this.access = 'rw',
    this.description,
    this.bitFields,
  });

  factory RegisterDef.fromJson(Map<String, dynamic> json) {
    return RegisterDef(
      address: json['address'] as int,
      name: json['name'] as String,
      size: json['size'] as int? ?? 4,
      access: json['access'] as String? ?? 'rw',
      description: json['description'] as String?,
      bitFields: json['bitFields'] != null
          ? Map<int, String>.from(json['bitFields'])
          : null,
    );
  }
}

/// AT 命令定义
class AtCommandDef {
  final String command; // 完整 AT 命令字符串，如 "AT+VERSION?"
  final String? responsePrefix;
  final String? description;
  final List<String>? params;

  const AtCommandDef({
    required this.command,
    this.responsePrefix,
    this.description,
    this.params,
  });
}

/// 厂商信息
class VendorInfo {
  final String vendorName;
  final String chipSeries;
  final String protocolVersion;
  final String? website;
  final String? description;

  const VendorInfo({
    required this.vendorName,
    required this.chipSeries,
    required this.protocolVersion,
    this.website,
    this.description,
  });
}

/// 完整协议定义
class ProtocolDef {
  final String id;
  final String name;
  final VendorInfo vendor;
  final List<GattServiceDef> services;
  final List<FrameFormatDef> frameFormats;
  final List<CommandGroup> commandGroups;
  final List<RegisterDef> registers;
  final List<AtCommandDef> atCommands;
  final String? notes;

  const ProtocolDef({
    required this.id,
    required this.name,
    required this.vendor,
    required this.services,
    required this.frameFormats,
    required this.commandGroups,
    required this.registers,
    required this.atCommands,
    this.notes,
  });

  factory ProtocolDef.fromJson(Map<String, dynamic> json) {
    return ProtocolDef(
      id: json['id'] as String,
      name: json['name'] as String,
      vendor: VendorInfo(
        vendorName: json['vendor']['vendorName'] as String,
        chipSeries: json['vendor']['chipSeries'] as String,
        protocolVersion: json['vendor']['protocolVersion'] as String,
        website: json['vendor']['website'] as String?,
        description: json['vendor']['description'] as String?,
      ),
      services: (json['services'] as List)
          .map((s) => GattServiceDef.fromJson(s as Map<String, dynamic>))
          .toList(),
      frameFormats: (json['frameFormats'] as List)
          .map((f) => FrameFormatDef.fromJson(f as Map<String, dynamic>))
          .toList(),
      commandGroups: (json['commandGroups'] as List).map((g) {
        final gj = g as Map<String, dynamic>;
        return CommandGroup(
          name: gj['name'] as String,
          description: gj['description'] as String?,
          opCodeRangeStart: gj['opCodeRangeStart'] as int?,
          opCodeRangeEnd: gj['opCodeRangeEnd'] as int?,
          commands: (gj['commands'] as List)
              .map((c) => CommandDef.fromJson(c as Map<String, dynamic>))
              .toList(),
        );
      }).toList(),
      registers: (json['registers'] as List? ?? [])
          .map((r) => RegisterDef.fromJson(r as Map<String, dynamic>))
          .toList(),
      atCommands: (json['atCommands'] as List? ?? [])
          .map((a) => AtCommandDef(
                command: a['command'] as String,
                responsePrefix: a['responsePrefix'] as String?,
                description: a['description'] as String?,
                params: a['params'] != null
                    ? List<String>.from(a['params'])
                    : null,
              ))
          .toList(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'vendor': {
          'vendorName': vendor.vendorName,
          'chipSeries': vendor.chipSeries,
          'protocolVersion': vendor.protocolVersion,
          if (vendor.website != null) 'website': vendor.website,
          if (vendor.description != null) 'description': vendor.description,
        },
        'services': services
            .map((s) => {
                  'name': s.name,
                  'uuid': s.uuid,
                  if (s.description != null) 'description': s.description,
                  'characteristics': s.characteristics
                      .map((c) => {
                            'name': c.name,
                            'uuid': c.uuid,
                            'direction': c.direction,
                            if (c.description != null)
                              'description': c.description,
                            if (c.writePayloadFormat != null)
                              'writePayloadFormat': c.writePayloadFormat,
                            if (c.notifyPayloadFormat != null)
                              'notifyPayloadFormat': c.notifyPayloadFormat,
                          })
                      .toList(),
                })
            .toList(),
        'frameFormats': frameFormats.map((f) => f.toJson()).toList(),
        'commandGroups': commandGroups
            .map((g) => {
                  'name': g.name,
                  if (g.description != null) 'description': g.description,
                  if (g.opCodeRangeStart != null)
                    'opCodeRangeStart': g.opCodeRangeStart,
                  if (g.opCodeRangeEnd != null)
                    'opCodeRangeEnd': g.opCodeRangeEnd,
                  'commands': g.commands
                      .map((c) => {
                            'name': c.name,
                            'opCode': c.opCode,
                            'direction': c.direction,
                            if (c.description != null)
                              'description': c.description,
                            if (c.paramNames != null)
                              'paramNames': c.paramNames,
                            if (c.paramTypes != null)
                              'paramTypes': c.paramTypes,
                            if (c.responseMatch != null)
                              'responseMatch': c.responseMatch,
                          })
                      .toList(),
                })
            .toList(),
        'registers': registers
            .map((r) => {
                  'address': r.address,
                  'name': r.name,
                  'size': r.size,
                  'access': r.access,
                  if (r.description != null) 'description': r.description,
                  if (r.bitFields != null) 'bitFields': r.bitFields,
                })
            .toList(),
        'atCommands': atCommands
            .map((a) => {
                  'command': a.command,
                  if (a.responsePrefix != null)
                    'responsePrefix': a.responsePrefix,
                  if (a.description != null) 'description': a.description,
                  if (a.params != null) 'params': a.params,
                })
            .toList(),
        if (notes != null) 'notes': notes,
      };
}

// ============================================================
// 帧解析器
// ============================================================

/// 解析后的帧字段值
class ParsedField {
  final String name;
  final dynamic value;
  final String displayValue; // 格式化显示
  final String? enumLabel; // 枚举标注

  const ParsedField({
    required this.name,
    required this.value,
    required this.displayValue,
    this.enumLabel,
  });
}

/// 帧解析结果
class ParsedFrame {
  final String formatName;
  final List<ParsedField> fields;
  final Uint8List rawBytes;
  final bool checksumValid;
  final String? error;

  const ParsedFrame({
    required this.formatName,
    required this.fields,
    required this.rawBytes,
    this.checksumValid = true,
    this.error,
  });
}

/// CRC-16/IBM 计算器 (BES 使用)
class CRC16IBM {
  static int compute(Uint8List data) {
    int crc = 0x0000;
    for (int i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc;
  }
}

/// CRC-8 计算器
class CRC8 {
  static int compute(Uint8List data) {
    int crc = 0x00;
    for (int i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x80) != 0) {
          crc = (crc << 1) ^ 0x07;
        } else {
          crc <<= 1;
        }
      }
    }
    return crc & 0xFF;
  }
}

/// 校验和计算
class ChecksumHelper {
  static int compute(Uint8List data, ChecksumType type,
      {int poly = 0xA001, int init = 0x0000, bool reflect = true}) {
    switch (type) {
      case ChecksumType.none:
        return 0;
      case ChecksumType.crc8:
        return CRC8.compute(data);
      case ChecksumType.crc16_ibm:
        return CRC16IBM.compute(data);
      case ChecksumType.xor8:
        return data.fold<int>(0, (p, b) => p ^ b);
      case ChecksumType.sum8:
        return data.fold<int>(0, (p, b) => p + b) & 0xFF;
      default:
        return 0;
    }
  }
}

/// 协议解析引擎
class ProtocolParser {
  /// 从 JSON 字符串加载协议定义
  static ProtocolDef loadProtocol(String jsonStr) {
    final Map<String, dynamic> json = jsonDecode(jsonStr);
    return ProtocolDef.fromJson(json);
  }

  /// 按固定字段解析帧
  static ParsedFrame parseFrame(Uint8List data, FrameFormatDef format) {
    int offset = 0;
    final List<ParsedField> fields = [];
    bool checksumValid = true;

    try {
      // 检查魔术字
      if (format.magicByte != null) {
        if (offset >= data.length || data[offset] != format.magicByte) {
          return ParsedFrame(
            formatName: format.name,
            fields: fields,
            rawBytes: data,
            error: '魔术字不匹配: 期望 0x${format.magicByte?.toRadixString(16).padLeft(2, '0')}',
          );
        }
        fields.add(ParsedField(
          name: 'magic',
          value: data[offset],
          displayValue: '0x${data[offset].toRadixString(16).padLeft(2, '0').toUpperCase()}',
          enumLabel: '帧头',
        ));
        offset++;
      }

      if (format.magicBytes != null) {
        for (int i = 0; i < format.magicBytes!.length; i++) {
          if (offset + i >= data.length ||
              data[offset + i] != format.magicBytes![i]) {
            return ParsedFrame(
              formatName: format.name,
              fields: fields,
              rawBytes: data,
              error: '魔术字节不匹配',
            );
          }
        }
        fields.add(ParsedField(
          name: 'magic',
          value: format.magicBytes,
          displayValue: format.magicBytes!
              .map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}')
              .join(' '),
          enumLabel: '帧头',
        ));
        offset += format.magicBytes!.length;
      }

      // 解析各字段
      for (final field in format.fields) {
        final result = _parseField(data, offset, field);
        fields.add(result);
        offset += _fieldByteSize(result.value, field);
      }

      // 校验 checksum
      int checksumDataEnd;
      if (format.checksumOffset >= 0 && format.checksumOffset < fields.length) {
        final csField = fields[format.checksumOffset];
        int expectedChecksum = _checksumValue(csField.value);
        int payloadLen = _calculatePayloadEnd(fields, format.checksumOffset);
        Uint8List payload = data.sublist(0, payloadLen);
        int computed =
            ChecksumHelper.compute(payload, format.checksumType);
        checksumValid = expectedChecksum == computed;
      }

      return ParsedFrame(
        formatName: format.name,
        fields: fields,
        rawBytes: data,
        checksumValid: checksumValid,
      );
    } catch (e) {
      return ParsedFrame(
        formatName: format.name,
        fields: fields,
        rawBytes: data,
        error: e.toString(),
      );
    }
  }

  /// 自动识别帧格式并解析
  static ParsedFrame? parseAuto(
      Uint8List data, List<FrameFormatDef> formats) {
    for (final format in formats) {
      if (format.magicByte != null && data.isNotEmpty) {
        if (data[0] == format.magicByte) {
          final result = parseFrame(data, format);
          if (result.error == null) return result;
        }
      }
      if (format.magicBytes != null && data.length >= format.magicBytes!.length) {
        bool match = true;
        for (int i = 0; i < format.magicBytes!.length; i++) {
          if (data[i] != format.magicBytes![i]) {
            match = false;
            break;
          }
        }
        if (match) {
          final result = parseFrame(data, format);
          if (result.error == null) return result;
        }
      }
    }
    return null;
  }

  /// 根据 opCode 查找命令定义
  static CommandDef? findCommand(int opCode, List<CommandGroup> groups) {
    for (final group in groups) {
      for (final cmd in group.commands) {
        if (cmd.opCode == opCode) return cmd;
      }
    }
    return null;
  }

  /// 根据地址查找寄存器定义
  static RegisterDef? findRegister(int address, List<RegisterDef> registers) {
    for (final reg in registers) {
      if (reg.address == address) return reg;
    }
    return null;
  }

  /// 从 hex 字符串解析数据包
  static Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '').replaceAll('0x', '');
    final List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, min(i + 2, hex.length)), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// 字节数组转 hex 字符串
  static String bytesToHex(Uint8List bytes, {String separator = ' '}) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(separator);
  }

  // --- Private ---

  static ParsedField _parseField(
      Uint8List data, int offset, FrameFieldDef field) {
    int len = field.byteLength;
    if (len == 0) len = data.length - offset; // 变长取剩余

    switch (field.encoding) {
      case FieldEncoding.uint8:
        final v = data[offset];
        return ParsedField(
          name: field.name,
          value: v,
          displayValue: '0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}',
          enumLabel: field.enumMap?[v],
        );

      case FieldEncoding.uint16:
        final v = field.endian == Endianness.big
            ? (data[offset] << 8) | data[offset + 1]
            : data[offset] | (data[offset + 1] << 8);
        return ParsedField(
          name: field.name,
          value: v,
          displayValue:
              '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()} ($v)',
          enumLabel: field.enumMap?[v],
        );

      case FieldEncoding.uint32:
        final v = field.endian == Endianness.big
            ? (data[offset] << 24) |
                (data[offset + 1] << 16) |
                (data[offset + 2] << 8) |
                data[offset + 3]
            : data[offset] |
                (data[offset + 1] << 8) |
                (data[offset + 2] << 16) |
                (data[offset + 3] << 24);
        return ParsedField(
          name: field.name,
          value: v,
          displayValue:
              '0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()} ($v)',
          enumLabel: field.enumMap?[v],
        );

      case FieldEncoding.hex:
      case FieldEncoding.bytes:
        final bytes = data.sublist(offset, offset + len);
        return ParsedField(
          name: field.name,
          value: bytes,
          displayValue: bytesToHex(bytes),
        );

      case FieldEncoding.ascii:
      case FieldEncoding.utf8:
        final str =
            String.fromCharCodes(data.sublist(offset, offset + len));
        return ParsedField(
          name: field.name,
          value: str,
          displayValue: str,
        );
    }
  }

  static int _fieldByteSize(dynamic value, FrameFieldDef field) {
    if (field.byteLength > 0) return field.byteLength;
    switch (field.encoding) {
      case FieldEncoding.uint8:
        return 1;
      case FieldEncoding.uint16:
        return 2;
      case FieldEncoding.uint32:
        return 4;
      case FieldEncoding.hex:
      case FieldEncoding.bytes:
        return (value is Uint8List) ? value.length : 0;
      case FieldEncoding.ascii:
      case FieldEncoding.utf8:
        return (value is String) ? value.length : 0;
    }
  }

  static int _checksumValue(dynamic value) {
    if (value is int) return value;
    if (value is Uint8List && value.length == 2) {
      return value[0] | (value[1] << 8);
    }
    return 0;
  }

  static int _calculatePayloadEnd(
      List<ParsedField> fields, int checksumIndex) {
    int offset = 0;
    for (int i = 0; i < checksumIndex; i++) {
      final v = fields[i].value;
      if (v is int) {
        offset += 1;
      } else if (v is Uint8List) {
        offset += v.length;
      } else if (v is String) {
        offset += v.length;
      }
    }
    return offset;
  }
}

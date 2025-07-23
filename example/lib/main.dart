import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thermal_printer_plus/esc_pos_utils_platform/esc_pos_utils_platform.dart';
import 'package:thermal_printer_plus/thermal_printer.dart';
import 'package:image/image.dart' as img;
import 'package:dart_ping_ios/dart_ping_ios.dart';
import 'image_utils.dart';

void main() {
  // Register DartPingIOS
  if (Platform.isIOS) {
    DartPingIOS.register();
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Printer Type [bluetooth, usb, network]
  var defaultPrinterType = PrinterType.bluetooth;
  var _isBle = false;
  var _reconnect = false;
  var _isConnected = false;
  var printerManager = PrinterManager.instance;
  var devices = <BluetoothPrinter>[];
  StreamSubscription<PrinterDevice>? _subscription;
  StreamSubscription<BTStatus>? _subscriptionBtStatus;
  StreamSubscription<USBStatus>? _subscriptionUsbStatus;
  StreamSubscription<TCPStatus>? _subscriptionTCPStatus;
  BTStatus _currentStatus = BTStatus.none;
  // ignore: unused_field
  TCPStatus _currentTCPStatus = TCPStatus.none;
  // _currentUsbStatus is only supports on Android
  // ignore: unused_field
  USBStatus _currentUsbStatus = USBStatus.none;
  List<int>? pendingTask;
  String _ipAddress = '';
  String _port = '9100';
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  BluetoothPrinter? selectedPrinter;
  late String assetPath = 'assets/ic_launcher.png';
  late List<String> assets = [
    'assets/ic_launcher.png',
    'assets/logo.png',
    'assets/resize_receipt.png',
    'assets/long_receipt.png',
    'assets/double_long_receipt.png',
    'assets/receipt.png',
  ];

  @override
  void initState() {
    if (Platform.isWindows) defaultPrinterType = PrinterType.usb;
    super.initState();
    _portController.text = _port;
    _scan();

    // subscription to listen change status of bluetooth connection
    _subscriptionBtStatus =
        PrinterManager.instance.stateBluetooth.listen((status) {
      log(' ----------------- status bt $status ------------------ ');
      _currentStatus = status;
      if (status == BTStatus.connected) {
        setState(() {
          _isConnected = true;
        });
      }
      if (status == BTStatus.none) {
        setState(() {
          _isConnected = false;
        });
      }
      if (status == BTStatus.connected && pendingTask != null) {
        if (Platform.isAndroid) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            PrinterManager.instance
                .send(type: PrinterType.bluetooth, bytes: pendingTask!);
            pendingTask = null;
          });
        } else if (Platform.isIOS) {
          PrinterManager.instance
              .send(type: PrinterType.bluetooth, bytes: pendingTask!);
          pendingTask = null;
        }
      }
    });
    //  PrinterManager.instance.stateUSB is only supports on Android
    _subscriptionUsbStatus = PrinterManager.instance.stateUSB.listen((status) {
      log(' ----------------- status usb $status ------------------ ');
      _currentUsbStatus = status;
      if (Platform.isAndroid) {
        if (status == USBStatus.connected && pendingTask != null) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            PrinterManager.instance
                .send(type: PrinterType.usb, bytes: pendingTask!);
            pendingTask = null;
          });
        }
      }
    });

    //  PrinterManager.instance.stateUSB is only supports on Android
    _subscriptionTCPStatus = PrinterManager.instance.stateTCP.listen((status) {
      log(' ----------------- status tcp $status ------------------ ');
      _currentTCPStatus = status;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscriptionBtStatus?.cancel();
    _subscriptionUsbStatus?.cancel();
    _subscriptionTCPStatus?.cancel();
    _portController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  // method to scan devices according PrinterType
  void _scan() {
    devices.clear();
    _subscription = printerManager
        .discovery(type: defaultPrinterType, isBle: _isBle)
        .listen((device) {
      print({
        "device.name": device.name,
        "device.address": device.address,
        "device.operatingSystem": device.operatingSystem,
        "device.vendorId": device.vendorId,
        "device.productId": device.productId,
      });
      devices.add(BluetoothPrinter(
        deviceName: device.name,
        address: device.address,
        isBle: _isBle,
        vendorId: device.vendorId,
        productId: device.productId,
        typePrinter: defaultPrinterType,
      ));
      setState(() {});
    });
  }

  void setPort(String value) {
    if (value.isEmpty) value = '9100';
    _port = value;
    var device = BluetoothPrinter(
      deviceName: value,
      address: _ipAddress,
      port: _port,
      typePrinter: PrinterType.network,
      state: false,
    );
    selectDevice(device);
  }

  void setIpAddress(String value) {
    _ipAddress = value;
    var device = BluetoothPrinter(
      deviceName: value,
      address: _ipAddress,
      port: _port,
      typePrinter: PrinterType.network,
      state: false,
    );
    selectDevice(device);
  }

  void selectDevice(BluetoothPrinter device) async {
    if (selectedPrinter != null) {
      if ((device.address != selectedPrinter!.address) ||
          (device.typePrinter == PrinterType.usb &&
              selectedPrinter!.vendorId != device.vendorId)) {
        await PrinterManager.instance
            .disconnect(type: selectedPrinter!.typePrinter);
      }
    }

    selectedPrinter = device;
    setState(() {});
  }

  generate() async {
    List<int> bytes = [];

    // Xprinter XP-N160I
    final profile = await CapabilityProfile.load(name: 'XP-N160I');

    // PaperSize.mm80 or PaperSize.mm58
    final generator = Generator(PaperSize.mm58, profile);
    bytes += generator.setGlobalCodeTable('CP1252');
    bytes += generator.text('Test Print',
        styles: const PosStyles(align: PosAlign.left));
    bytes += generator.text('Product 1');
    bytes += generator.text('Product 2');

    print("=========bytes");
    print(bytes);
    print("=========bytes");

    final printable = bytes.where((b) => b >= 32 && b <= 126).toList();

    print("=========printable");
    print(bytes.map((e) => String.fromCharCode(e)));
    print("=========printable");
  }

  Future _printReceiveTest() async {
    List<int> bytes = [];

    // Xprinter XP-N160I
    final profile = await CapabilityProfile.load(name: 'XP-N160I');

    // PaperSize.mm80 or PaperSize.mm58
    final generator = Generator(PaperSize.mm58, profile);
    bytes += generator.setGlobalCodeTable('CP1252');
    bytes += generator.text('Test Print',
        styles: const PosStyles(align: PosAlign.left));
    bytes += generator.text('Product 1');
    bytes += generator.text('Product 2');

    // bytes += generator.text('￥1,990', containsChinese: true, styles: const PosStyles(align: PosAlign.left));
    // bytes += generator.emptyLines(1);

    // sum width total column must be 12
    bytes += generator.row([
      PosColumn(
          width: 8,
          text: 'Lemon lime export quality per pound x 5 units',
          styles: const PosStyles(align: PosAlign.left, codeTable: 'CP1252')),
      PosColumn(
          width: 4,
          text: 'USD 2.00',
          styles: const PosStyles(align: PosAlign.right, codeTable: 'CP1252')),
    ]);

    final ByteData data = await rootBundle.load(assetPath);
    if (data.lengthInBytes > 0) {
      final Uint8List imageBytes = data.buffer.asUint8List();
      // decode the bytes into an image
      final decodedImage = img.decodeImage(imageBytes)!;
      // Create a black bottom layer
      // Resize the image to a 130x? thumbnail (maintaining the aspect ratio).
      img.Image thumbnail = img.copyResize(decodedImage, height: 130);
      // creates a copy of the original image with set dimensions
      img.Image originalImg =
          img.copyResize(decodedImage, width: 380, height: 130);
      // fills the original image with a white background
      img.fill(originalImg, color: img.ColorRgb8(255, 255, 255));
      var padding = (originalImg.width - thumbnail.width) / 2;

      //insert the image inside the frame and center it
      drawImage(originalImg, thumbnail, dstX: padding.toInt());

      // convert image to grayscale
      var grayscaleImage = img.grayscale(originalImg);

      bytes += generator.feed(1);
      // bytes += generator.imageRaster(img.decodeImage(imageBytes)!, align: PosAlign.center);
      bytes += generator.imageRaster(grayscaleImage, align: PosAlign.center);
      bytes += generator.feed(1);
    }

    // // Chinese characters
    bytes += generator.row([
      PosColumn(
          width: 8,
          text: '豚肉・木耳と玉子炒め弁当',
          styles: const PosStyles(align: PosAlign.left),
          containsChinese: true),
      PosColumn(
          width: 4,
          text: '￥1,990',
          styles: const PosStyles(align: PosAlign.right),
          containsChinese: true),
    ]);
    _printEscPos(bytes, generator);
  }

  _printReceipt() async {
    var bytes = await generateReceipt();
    if (bytes.isEmpty) {
      log("No bytes generated for receipt");
      return;
    }
    final profile = await CapabilityProfile.load();

    final generator = Generator(PaperSize.mm58, profile);
    _printEscPos(bytes, generator);
  }

  Future<List<int>> generateReceipt() async {
    // Print image:
    final ByteData _data = await rootBundle.load(assetPath);
    final Uint8List _imgBytes = _data.buffer.asUint8List();
    var data = await generateImageToESCByte(_imgBytes,
        paperSize: PaperSize.mm58, autoCut: false, feedLine: 0, beepN: 0);

    return data;
  }

  Future<List<int>> generateImageToESCByte(
    Uint8List imgBytes, {
    PaperSize paperSize = PaperSize.mm80,
    bool autoCut = true,
    bool autoDrawer = false,
    int feedLine = 2,
    int beepN = 0,
    Function(Object object)? logger,
    CapabilityProfile? profile,
  }) async {
    try {
      logger?.call("generateImageToESCByte");
      final _profile = (profile ?? await CapabilityProfile.load());
      final generator = Generator(paperSize, _profile);
      List<int> bytes = [];

      if (imgBytes.isNotEmpty) {
        // Print image:
        final img.Image image = img.decodeImage(imgBytes)!;
        // Print image using an alternative (obsolette) command
        // okay
        final width = image.width;
        final height = image.height;
        var ratio = width / height;

        final copies =
            img.copyResize(image, width: paperSize.width, maintainAspect: true);
        logger?.call({
          "width": width,
          "height": height,
          "ratio": ratio,
          "copies.width": copies.width,
          "copies.height": copies.height,
          "image.getBytes()": image.getBytes().lengthInBytes,
          "copies.getBytes()": copies.getBytes().lengthInBytes,
        });

        /// use compute if freeze ui
        ///  await compute((v) {
        ///   return img.copyResize(v, width: 572, maintainAspect: true);
        /// }, image);
        logger?.call("<===== generator.imageRaster");

        /// chunk to avoid maxium send
        // Calculate the number of chunks
        int chunkCount = (copies.height / copies.width).ceil();
        // Initialize an empty list to store the chunks
        List<img.Image> chunks = [];

        // Check if the height is greater than the width
        if (copies.height > paperSize.width) {
          // Loop through each chunk
          for (int i = 0; i < chunkCount; i++) {
            // Calculate the y position of the current chunk
            int yPos = i * paperSize.width;

            // Calculate the height of the current chunk
            int height = (i == chunkCount - 1)
                ? copies.height - yPos // last chunk
                : paperSize.width;

            // Crop the image
            final crop = img.copyCrop(
              copies,
              x: 0,
              y: yPos,
              width: paperSize.width,
              height: height,
            );

            // Add the chunk to the list
            chunks.add(crop);
            bytes += await generator.imageRaster(crop);
          }
        } else {
          List<img.Image> chunks = [copies];
          bytes += await generator.imageRaster(copies);
        }
        logger?.call("generator.imageRaster ======>");
      }

      if (feedLine > 0) {
        bytes += generator.feed(feedLine);
      }
      if (autoCut) {
        bytes += generator.cut();
      }
      if (autoDrawer) {
        bytes += generator.drawer();
      }

      if (beepN > 0) {
        bytes += generator.beep(n: beepN);
      }

      return bytes;
    } catch (exception, stackTrace) {
      logger?.call("exception: $exception");
      logger?.call("stackTrace: $stackTrace");
      throw exception;
    }
  }

  /// print ticket
  void _printEscPos(List<int> bytes, Generator generator) async {
    var connectedTCP = false;
    if (selectedPrinter == null) return;
    var bluetoothPrinter = selectedPrinter!;

    switch (bluetoothPrinter.typePrinter) {
      case PrinterType.usb:
        bytes += generator.feed(2);
        bytes += generator.cut();
        await printerManager.connect(
            type: bluetoothPrinter.typePrinter,
            model: UsbPrinterInput(
                name: bluetoothPrinter.deviceName,
                productId: bluetoothPrinter.productId,
                vendorId: bluetoothPrinter.vendorId));
        pendingTask = null;
        break;
      case PrinterType.bluetooth:
        bytes += generator.cut();
        await printerManager.connect(
            type: bluetoothPrinter.typePrinter,
            model: BluetoothPrinterInput(
                name: bluetoothPrinter.deviceName,
                address: bluetoothPrinter.address!,
                isBle: bluetoothPrinter.isBle ?? false,
                autoConnect: _reconnect));
        pendingTask = null;
        if (Platform.isAndroid) pendingTask = bytes;
        break;
      case PrinterType.network:
        bytes += generator.feed(2);
        bytes += generator.cut();
        connectedTCP = await printerManager.connect(
            type: bluetoothPrinter.typePrinter,
            model: TcpPrinterInput(ipAddress: bluetoothPrinter.address!));
        if (!connectedTCP) print(' --- please review your connection ---');
        break;
      default:
    }
    if (bluetoothPrinter.typePrinter == PrinterType.bluetooth &&
        Platform.isAndroid) {
      if (_currentStatus == BTStatus.connected) {
        printerManager.send(type: bluetoothPrinter.typePrinter, bytes: bytes);
        pendingTask = null;
      }
    } else {
      printerManager.send(type: bluetoothPrinter.typePrinter, bytes: bytes);
    }
  }

  // conectar dispositivo
  _connectDevice() async {
    _isConnected = false;
    if (selectedPrinter == null) return;
    switch (selectedPrinter!.typePrinter) {
      case PrinterType.usb:
        await printerManager.connect(
            type: selectedPrinter!.typePrinter,
            model: UsbPrinterInput(
                name: selectedPrinter!.deviceName,
                productId: selectedPrinter!.productId,
                vendorId: selectedPrinter!.vendorId));
        _isConnected = true;
        break;
      case PrinterType.bluetooth:
        await printerManager.connect(
            type: selectedPrinter!.typePrinter,
            model: BluetoothPrinterInput(
                name: selectedPrinter!.deviceName,
                address: selectedPrinter!.address!,
                isBle: selectedPrinter!.isBle ?? false,
                autoConnect: _reconnect));
        break;
      case PrinterType.network:
        await printerManager.connect(
            type: selectedPrinter!.typePrinter,
            model: TcpPrinterInput(ipAddress: selectedPrinter!.address!));
        _isConnected = true;
        break;
      default:
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Pos Plugin Platform example app'),
        ),
        body: Center(
          child: Container(
            height: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: OutlinedButton(
                        onPressed: generate, child: Text("generate")),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedPrinter == null || _isConnected
                                ? null
                                : () {
                                    _connectDevice();
                                  },
                            child: const Text("Connect",
                                textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedPrinter == null || !_isConnected
                                ? null
                                : () {
                                    if (selectedPrinter != null)
                                      printerManager.disconnect(
                                          type: selectedPrinter!.typePrinter);
                                    setState(() {
                                      _isConnected = false;
                                    });
                                  },
                            child: const Text("Disconnect",
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownButtonFormField<PrinterType>(
                    value: defaultPrinterType,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.print,
                        size: 24,
                      ),
                      labelText: "Type Printer Device",
                      labelStyle: TextStyle(fontSize: 18.0),
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                    ),
                    items: <DropdownMenuItem<PrinterType>>[
                      if (Platform.isAndroid || Platform.isIOS)
                        const DropdownMenuItem(
                          value: PrinterType.bluetooth,
                          child: Text("bluetooth"),
                        ),
                      if (Platform.isAndroid || Platform.isWindows)
                        const DropdownMenuItem(
                          value: PrinterType.usb,
                          child: Text("usb"),
                        ),
                      const DropdownMenuItem(
                        value: PrinterType.network,
                        child: Text("Wifi"),
                      ),
                    ],
                    onChanged: (PrinterType? value) {
                      setState(() {
                        if (value != null) {
                          setState(() {
                            defaultPrinterType = value;
                            selectedPrinter = null;
                            _isBle = false;
                            _isConnected = false;
                            _scan();
                          });
                        }
                      });
                    },
                  ),
                  Visibility(
                    visible: defaultPrinterType == PrinterType.bluetooth &&
                        Platform.isAndroid,
                    child: SwitchListTile.adaptive(
                      contentPadding:
                          const EdgeInsets.only(bottom: 20.0, left: 20),
                      title: const Text(
                        "This device supports ble (low energy)",
                        textAlign: TextAlign.start,
                        style: TextStyle(fontSize: 19.0),
                      ),
                      value: _isBle,
                      onChanged: (bool? value) {
                        setState(() {
                          _isBle = value ?? false;
                          _isConnected = false;
                          selectedPrinter = null;
                          _scan();
                        });
                      },
                    ),
                  ),
                  Visibility(
                    visible: defaultPrinterType == PrinterType.bluetooth &&
                        Platform.isAndroid,
                    child: SwitchListTile.adaptive(
                      contentPadding:
                          const EdgeInsets.only(bottom: 20.0, left: 20),
                      title: const Text(
                        "reconnect",
                        textAlign: TextAlign.start,
                        style: TextStyle(fontSize: 19.0),
                      ),
                      value: _reconnect,
                      onChanged: (bool? value) {
                        setState(() {
                          _reconnect = value ?? false;
                        });
                      },
                    ),
                  ),

                  /// Dropdown to select an asset image
                  const SizedBox(height: 10),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      setState(() {
                        assetPath = value;
                        log("Selected asset: $assetPath");
                      });
                    },
                    itemBuilder: (_) => assets
                        .map((e) => PopupMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    child: ListTile(
                      title: Text(
                        "Selected asset: $assetPath",
                        style: const TextStyle(fontSize: 16),
                      ),
                      leading: const Icon(Icons.image, size: 24),
                    ),
                  ),
                  Column(
                      children: devices
                          .map(
                            (device) => ListTile(
                              title: Text('${device.deviceName}'),
                              subtitle: Platform.isAndroid &&
                                      defaultPrinterType == PrinterType.usb
                                  ? null
                                  : Visibility(
                                      visible: !Platform.isWindows,
                                      child: Text("${device.address}")),
                              onTap: () {
                                // do something
                                selectDevice(device);
                              },
                              leading: selectedPrinter != null &&
                                      ((device.typePrinter == PrinterType.usb &&
                                                  Platform.isWindows
                                              ? device.deviceName ==
                                                  selectedPrinter!.deviceName
                                              : device.vendorId != null &&
                                                  selectedPrinter!.vendorId ==
                                                      device.vendorId) ||
                                          (device.address != null &&
                                              selectedPrinter!.address ==
                                                  device.address))
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                    )
                                  : null,
                              trailing: OutlinedButton(
                                onPressed: selectedPrinter == null ||
                                        device.deviceName !=
                                            selectedPrinter?.deviceName
                                    ? null
                                    : () async {
                                        // _printReceiveTest();
                                        _printReceipt();
                                      },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 20),
                                  child: Text("Print test ticket",
                                      textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                          )
                          .toList()),
                  Visibility(
                    visible: defaultPrinterType == PrinterType.network &&
                        Platform.isWindows,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: TextFormField(
                        controller: _ipController,
                        keyboardType:
                            const TextInputType.numberWithOptions(signed: true),
                        decoration: const InputDecoration(
                          label: Text("Ip Address"),
                          prefixIcon: Icon(Icons.wifi, size: 24),
                        ),
                        onChanged: setIpAddress,
                      ),
                    ),
                  ),
                  Visibility(
                    visible: defaultPrinterType == PrinterType.network &&
                        Platform.isWindows,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: TextFormField(
                        controller: _portController,
                        keyboardType:
                            const TextInputType.numberWithOptions(signed: true),
                        decoration: const InputDecoration(
                          label: Text("Port"),
                          prefixIcon: Icon(Icons.numbers_outlined, size: 24),
                        ),
                        onChanged: setPort,
                      ),
                    ),
                  ),
                  Visibility(
                    visible: defaultPrinterType == PrinterType.network &&
                        Platform.isWindows,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: OutlinedButton(
                        onPressed: () async {
                          if (_ipController.text.isNotEmpty)
                            setIpAddress(_ipController.text);
                          _printReceiveTest();
                        },
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: 4, horizontal: 50),
                          child: Text("Print test ticket",
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BluetoothPrinter {
  int? id;
  String? deviceName;
  String? address;
  String? port;
  String? vendorId;
  String? productId;
  bool? isBle;

  PrinterType typePrinter;
  bool? state;

  BluetoothPrinter(
      {this.deviceName,
      this.address,
      this.port,
      this.state,
      this.vendorId,
      this.productId,
      this.typePrinter = PrinterType.bluetooth,
      this.isBle = false});
}

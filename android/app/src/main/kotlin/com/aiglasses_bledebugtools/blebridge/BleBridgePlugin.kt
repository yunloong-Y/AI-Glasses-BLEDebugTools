package com.aiglasses_bledebugtools.blebridge

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

/**
 * AI-Glasses-BLEDebugTools Android BLE Bridge
 *
 * 封装 Android BluetoothGatt API，为 Flutter 层提供统一的 BLE 操作接口。
 * 支持扫描、连接、GATT 读写、通知订阅、OTA 升级。
 *
 * 适配 Android 9 ~ Android 15
 */

class BleBridge(private val context: Context) {

    companion object {
        private const val TAG = "AI-Glasses-BLEDebugTools/BleBridge"
    }

    private val bluetoothManager: BluetoothManager? =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter

    private val connectedDevices = mutableMapOf<String, BluetoothGatt>()
    private val notifyStreams = mutableMapOf<String, EventChannel.EventSink>()

    /**
     * 开始 BLE 扫描
     */
    fun startScan(timeoutMs: Long, result: MethodChannel.Result) {
        if (bluetoothAdapter?.bluetoothLeScanner == null) {
            result.error("NO_BLE", "Bluetooth not available", null)
            return
        }

        val scanner = bluetoothAdapter.bluetoothLeScanner
        val foundDevices = mutableListOf<Map<String, Any>>()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                val deviceInfo = mapOf(
                    "mac" to device.address,
                    "name" to (device.name ?: "Unknown"),
                    "rssi" to result.rssi,
                    "advertiseData" to (result.scanRecord?.bytes?.toList() ?: emptyList<Byte>())
                )
                foundDevices.add(deviceInfo)
            }
        }

        scanner.startScan(callback)

        // 超时自动停止
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            scanner.stopScan(callback)
            result.success(foundDevices)
        }, timeoutMs)
    }

    /**
     * 连接设备
     */
    fun connect(mac: String, result: MethodChannel.Result) {
        val device = bluetoothAdapter?.getRemoteDevice(mac)
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found: $mac", null)
            return
        }

        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "Connected to $mac, discovering services...")
                        gatt.discoverServices()
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.i(TAG, "Disconnected from $mac")
                        connectedDevices.remove(mac)
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    connectedDevices[mac] = gatt
                    Log.i(TAG, "Services discovered for $mac")
                    result.success(true)
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                Log.i(TAG, "Char read: ${characteristic.uuid} = ${value.toHexString()}")
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                Log.i(TAG, "Char write: ${characteristic.uuid} status=$status")
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray
            ) {
                val key = "${mac}_${characteristic.uuid}"
                notifyStreams[key]?.success(value.toList())
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, false, gattCallback)
        }
    }

    /**
     * 断开设备
     */
    fun disconnect(mac: String) {
        connectedDevices[mac]?.let { gatt ->
            gatt.disconnect()
            gatt.close()
            connectedDevices.remove(mac)
        }
    }

    /**
     * 断开所有设备
     */
    fun disconnectAll() {
        connectedDevices.values.forEach { gatt ->
            gatt.disconnect()
            gatt.close()
        }
        connectedDevices.clear()
    }

    /**
     * 获取已连接设备列表
     */
    fun getConnectedDevices(): List<String> = connectedDevices.keys.toList()
}

// Extension: ByteArray to hex string
private fun ByteArray.toHexString(): String =
    joinToString(" ") { "%02x".format(it) }

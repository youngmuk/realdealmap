package com.realdealmap.realdealmap

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 위치 권한을 **단계로 나눠** 요청한다.
 *
 * 왜 직접 다루나: geolocator는 매니페스트에 선언된 위치 권한을 전부 한꺼번에
 * 요청한다(getLocationPermissionsFromManifest). 정밀 위치를 선언하는 순간
 * 첫 실행에서도 "정확한 위치" 창이 뜨는데, 우리가 방침에 적어 둔 것은
 * **지도의 현재 위치 버튼을 누른 사람에게만** 정밀 위치를 묻는다는 것이다.
 *
 * 그래서 위치 잡기는 geolocator에 두고 권한 요청만 여기로 가져온다.
 * 안드로이드가 정한 순서 그대로다 — 대략 위치를 먼저 받고, 나중에 정밀 위치를
 * 따로 요청하면 시스템이 "정확한 위치로 변경" 창을 띄운다.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status())
                    "requestCoarse" -> request(Manifest.permission.ACCESS_COARSE_LOCATION, result)
                    "requestFine" -> request(Manifest.permission.ACCESS_FINE_LOCATION, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** none · coarse · fine. 무엇까지 받았는지가 곧 좌표를 얼마나 믿을 수 있는지다. */
    private fun status(): String {
        val granted = { p: String ->
            ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED
        }
        return when {
            granted(Manifest.permission.ACCESS_FINE_LOCATION) -> "fine"
            granted(Manifest.permission.ACCESS_COARSE_LOCATION) -> "coarse"
            else -> "none"
        }
    }

    private fun request(permission: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(status())
            return
        }
        // 앞선 요청이 아직 안 끝났으면 새 것을 받지 않는다. 창이 겹쳐 뜨면
        // 어느 응답이 어느 요청의 것인지 알 수 없다.
        if (pending != null) {
            result.success(status())
            return
        }
        pending = result
        ActivityCompat.requestPermissions(this, arrayOf(permission), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val result = pending ?: return
        pending = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        // 거부됐는데 다시 물어볼 근거도 못 보이면 "다시 묻지 않기"다. 그때는
        // 앱에서 아무리 요청해도 창이 안 뜨므로 설정으로 보내야 한다.
        val forever = !granted && permissions.isNotEmpty() &&
            !ActivityCompat.shouldShowRequestPermissionRationale(this, permissions[0])
        result.success(if (forever) "denied_forever" else status())
    }

    private companion object {
        const val CHANNEL = "realdealmap/location_permission"
        const val REQUEST_CODE = 4831
    }
}

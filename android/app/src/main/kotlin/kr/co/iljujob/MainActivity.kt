package kr.co.iljujob

import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.content.pm.PackageManager
import android.util.Base64
import android.util.Log
import java.security.MessageDigest
import android.content.pm.Signature
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // ✅ CHANNEL 중복 선언 제거 — 하나로 통합
    private val DEEPLINK_CHANNEL = "deeplink/albailju"
    private val KEYBOARD_CHANNEL = "com.iljujob/keyboard"

    private var deeplinkChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 딥링크 채널
        deeplinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEPLINK_CHANNEL
        )

        // ✅ 키보드 모드 채널
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEYBOARD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAdjustResize" -> {
                    window.setSoftInputMode(
                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                    )
                    result.success(null)
                }
                "setAdjustPan" -> {
                    window.setSoftInputMode(
                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, true)
        printKeyHashes()
        handleDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        intent?.data?.let { uri ->
            val uriStr = uri.toString()
            deeplinkChannel?.invokeMethod("onDeepLink", uriStr)
        }
    }

    private fun printKeyHashes() {
        try {
            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(
                        PackageManager.GET_SIGNING_CERTIFICATES.toLong()
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
            }

            val signatures: Array<Signature> =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pkgInfo.signingInfo?.apkContentsSigners ?: emptyArray()
                } else {
                    @Suppress("DEPRECATION")
                    pkgInfo.signatures ?: emptyArray()
                }

            val md = MessageDigest.getInstance("SHA")
            signatures.forEach { sig ->
                md.update(sig.toByteArray())
                val keyHash = Base64.encodeToString(md.digest(), Base64.NO_WRAP)
                Log.i("KeyHash", ">>> $keyHash")
            }
        } catch (e: Exception) {
            Log.e("KeyHash", "error", e)
        }
    }
}
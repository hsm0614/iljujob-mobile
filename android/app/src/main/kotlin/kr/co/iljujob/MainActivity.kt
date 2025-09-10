package kr.co.iljujob

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 👇 키 해시 로그용 import
import android.os.Build
import android.content.pm.PackageManager
import android.util.Base64
import android.util.Log
import java.security.MessageDigest
import android.content.pm.Signature

class MainActivity : FlutterActivity() {

    private val CHANNEL = "deeplink/albailju"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ✅ 실행중 키 해시 출력 (nullable/버전 호환)
        printKeyHashes()

        // 기존 딥링크 처리
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
            methodChannel?.invokeMethod("onDeepLink", uriStr)
        }
    }

    private fun printKeyHashes() {
        try {
            // API 33(TIRAMISU)+에서 flags API가 바뀜
            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            }

            // API 28(P)+에서는 signingInfo, 이하에서는 signatures 사용
            val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pkgInfo.signingInfo?.apkContentsSigners ?: emptyArray()  // ← 안전 호출
            } else {
                @Suppress("DEPRECATION")
                pkgInfo.signatures ?: emptyArray()
            }

            val md = MessageDigest.getInstance("SHA")
            signatures.forEach { sig ->
                md.update(sig.toByteArray())
                val keyHash = Base64.encodeToString(md.digest(), Base64.NO_WRAP)
                Log.i("KeyHash", ">>> $keyHash") // 이 값을 Kakao 콘솔 Android 플랫폼 '키 해시'에 추가
            }
        } catch (e: Exception) {
            Log.e("KeyHash", "error", e)
        }
    }
}

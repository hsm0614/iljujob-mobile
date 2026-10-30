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
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams

class MainActivity : FlutterActivity() {
    // ✅ CHANNEL 중복 선언 제거 — 하나로 통합
    private val DEEPLINK_CHANNEL = "deeplink/albailju"
    private val KEYBOARD_CHANNEL = "com.iljujob/keyboard"

    private var deeplinkChannel: MethodChannel? = null
    private var adBillingChannel: MethodChannel? = null
    private var adBillingClient: BillingClient? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        adBillingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "albailju/ad_billing")
        adBillingClient = BillingClient.newBuilder(this)
            .setListener(PurchasesUpdatedListener { result, purchases ->
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    purchases?.forEach { emitAdPurchase(it) }
                } else {
                    adBillingChannel?.invokeMethod("purchaseError", mapOf(
                        "code" to result.responseCode, "message" to result.debugMessage))
                }
            })
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        adBillingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "queryProduct", "purchase" -> {
                    val productId = call.argument<String>("productId") ?: ""
                    withBilling({ client ->
                        val params = QueryProductDetailsParams.newBuilder()
                            .setProductList(listOf(QueryProductDetailsParams.Product.newBuilder()
                                .setProductId(productId).setProductType(BillingClient.ProductType.INAPP).build()))
                            .build()
                        client.queryProductDetailsAsync(params) { billingResult, detailsResult ->
                            runOnUiThread {
                                val details = detailsResult.productDetailsList.firstOrNull()
                                val offer = details?.oneTimePurchaseOfferDetailsList?.firstOrNull()
                                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK || details == null || offer == null) {
                                    result.error("PRODUCT_UNAVAILABLE", "Play 상품을 불러오지 못했습니다.", null)
                                } else if (call.method == "queryProduct") {
                                    result.success(offer.formattedPrice)
                                } else {
                                    val item = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
                                    offer.offerToken?.let { item.setOfferToken(it) }
                                    val flow = BillingFlowParams.newBuilder()
                                        .setProductDetailsParamsList(listOf(item.build())).build()
                                    val launch = client.launchBillingFlow(this, flow)
                                    if (launch.responseCode == BillingClient.BillingResponseCode.OK) result.success(null)
                                    else result.error("PURCHASE_FAILED", launch.debugMessage, null)
                                }
                            }
                        }
                    }, result)
                }
                "restore" -> withBilling({ client ->
                    val params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
                    client.queryPurchasesAsync(params) { billingResult, purchases ->
                        runOnUiThread {
                            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                                purchases.forEach { emitAdPurchase(it) }
                                result.success(null)
                            } else result.error("RESTORE_FAILED", billingResult.debugMessage, null)
                        }
                    }
                }, result)
                "consume" -> withBilling({ client ->
                    val token = call.argument<String>("purchaseToken") ?: ""
                    client.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(token).build()) { billingResult, _ ->
                        runOnUiThread {
                            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) result.success(null)
                            else result.error("CONSUME_FAILED", billingResult.debugMessage, null)
                        }
                    }
                }, result)
                else -> result.notImplemented()
            }
        }

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

    private fun withBilling(action: (BillingClient) -> Unit, result: MethodChannel.Result) {
        val client = adBillingClient ?: return result.error("NO_BILLING", "Play 결제를 시작할 수 없습니다.", null)
        if (client.isReady) return action(client)
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                runOnUiThread {
                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) action(client)
                    else result.error("NO_BILLING", billingResult.debugMessage, null)
                }
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    private fun emitAdPurchase(purchase: Purchase) {
        val product = purchase.products.firstOrNull { it == "banner_home_30d" || it == "recruit_card_30d" } ?: return
        adBillingChannel?.invokeMethod("purchaseUpdated", mapOf(
            "productId" to product,
            "purchaseToken" to purchase.purchaseToken,
            "state" to purchase.purchaseState
        ))
    }

    override fun onDestroy() {
        adBillingClient?.endConnection()
        super.onDestroy()
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

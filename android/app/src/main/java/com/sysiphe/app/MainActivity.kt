package com.sysiphe.app

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    companion object {
        // Change targets.json sur GitHub pour changer la cible sans recompiler l'APK
        const val TARGETS_URL =
            "https://raw.githubusercontent.com/Mephisto116631/sysiphe/main/mobile/targets.json"
        const val FALLBACK_URL =
            "https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app"
        const val TIMEOUT_MS = 4000
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this)
        setContentView(webView)
        setupWebView()

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState)
        } else {
            // Résolution asynchrone : NAS si dispo, sinon Streamlit Cloud
            thread {
                val url = pickBestUrl()
                runOnUiThread { webView.loadUrl(url) }
            }
        }
    }

    /** Renvoie l'URL la plus disponible : NAS → cloud → fallback codé en dur. */
    private fun pickBestUrl(): String {
        val targets = fetchTargets() ?: return FALLBACK_URL
        val nasUrl   = targets.optString("nas", "")
        val cloudUrl = targets.optString("cloud", FALLBACK_URL)
        if (nasUrl.isNotEmpty() && isHealthy(nasUrl)) return nasUrl
        return cloudUrl
    }

    private fun fetchTargets(): JSONObject? = try {
        val conn = URL(TARGETS_URL).openConnection() as HttpURLConnection
        conn.connectTimeout = TIMEOUT_MS
        conn.readTimeout    = TIMEOUT_MS
        val body = conn.inputStream.bufferedReader().readText()
        conn.disconnect()
        JSONObject(body)
    } catch (_: Exception) { null }

    private fun isHealthy(baseUrl: String): Boolean = try {
        val conn = URL("$baseUrl/_stcore/health").openConnection() as HttpURLConnection
        conn.connectTimeout = TIMEOUT_MS
        conn.readTimeout    = TIMEOUT_MS
        val ok = conn.responseCode == 200
        conn.disconnect()
        ok
    } catch (_: Exception) { false }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        // Cookies persistants — survivent aux kills de processus Android
        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
        }

        webView.settings.apply {
            javaScriptEnabled   = true
            domStorageEnabled   = true   // localStorage actif → profil retenu sur le device
            databaseEnabled     = true
            cacheMode           = WebSettings.LOAD_DEFAULT
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
        }

        // Toute navigation reste dans le WebView
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = false
        }
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack() else super.onBackPressed()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        webView.saveState(outState)
    }

    override fun onPause() {
        super.onPause()
        CookieManager.getInstance().flush()
    }

    override fun onResume() {
        super.onResume()
        CookieManager.getInstance().flush()
    }
}

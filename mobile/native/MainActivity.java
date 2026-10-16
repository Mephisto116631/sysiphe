package com.medhi.sysiphe;

import android.net.Uri;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import androidx.browser.customtabs.CustomTabsIntent;
import com.getcapacitor.BridgeActivity;

/**
 * Ouvre Streamlit Cloud dans Chrome Custom Tabs plutôt que dans la WebView.
 *
 * Pourquoi : la WebView Android et Chrome utilisent des cookie jars séparés.
 * Streamlit Cloud vérifie un cookie de session posé par share.streamlit.io ;
 * ce cookie existe dans Chrome (l'utilisateur s'y est connecté une fois) mais
 * pas dans la WebView isolée → "You do not have access".
 *
 * Chrome Custom Tabs partage le cookie jar de Chrome → le gate Streamlit passe.
 * Pour le NAS (réseau local, sans auth), on laisse la WebView directe.
 */
public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WebView webView = getBridge().getWebView();

        // Cookies tiers (gardé comme filet de sécurité pour d'autres domaines)
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(webView, true);

        // Interface JS → natif : permet à index.html d'ouvrir Chrome Custom Tabs
        webView.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void openInBrowser(String url) {
                runOnUiThread(() -> {
                    new CustomTabsIntent.Builder()
                        .setShowTitle(false)
                        .build()
                        .launchUrl(MainActivity.this, Uri.parse(url));
                    // Minimise le launcher pour que le bouton Retour de CCT
                    // ramène à l'écran d'accueil Android (et non à la splash)
                    moveTaskToBack(true);
                });
            }
        }, "AndroidBridge");
    }
}

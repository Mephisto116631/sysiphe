package com.medhi.sysiphe;

import android.os.Bundle;
import android.webkit.CookieManager;
import com.getcapacitor.BridgeActivity;

/**
 * Autorise les cookies tiers dans la WebView : Streamlit Cloud pose son cookie
 * d'accès via share.streamlit.io, bloqué par défaut sur Android
 * ("You do not have access to this app or it does not exist").
 *
 * On corrige aussi l'user-agent : Android WebView inclut "Version/4.0" avant
 * "Chrome/...", ce qui indique à certains sites (dont Streamlit Cloud) qu'il
 * s'agit d'une WebView embarquée → ils forcent l'auth. On retire ce marqueur
 * pour que l'UA ressemble à un Chrome mobile classique.
 */
public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        android.webkit.WebView webView = getBridge().getWebView();

        // Cookies tiers (nécessaire pour le cookie de session Streamlit Cloud)
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(webView, true);

        // UA : retire "Version/4.0 " qui signale une WebView à Streamlit Cloud
        String ua = webView.getSettings().getUserAgentString();
        webView.getSettings().setUserAgentString(ua.replace("Version/4.0 ", ""));
    }
}

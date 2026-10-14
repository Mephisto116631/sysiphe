package com.medhi.sysiphe;

import android.os.Bundle;
import android.webkit.CookieManager;
import com.getcapacitor.BridgeActivity;

/**
 * Autorise les cookies tiers dans la WebView : Streamlit Cloud pose son cookie
 * d'accès via share.streamlit.io, bloqué par défaut sur Android
 * ("You do not have access to this app or it does not exist").
 */
public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(getBridge().getWebView(), true);
    }
}

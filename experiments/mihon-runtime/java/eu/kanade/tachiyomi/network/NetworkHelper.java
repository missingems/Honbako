package eu.kanade.tachiyomi.network;

import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;

/** Experimental host services for a controlled local extension test, not a production Android API. */
public final class NetworkHelper {
    private final OkHttpClient client = new OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false)
        .addInterceptor(chain -> {
            if (!chain.request().url().host().equals("127.0.0.1")) {
                throw new java.io.IOException("The host compatibility probe permits only 127.0.0.1");
            }
            return chain.proceed(chain.request());
        })
        .addInterceptor(new eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor())
        .addInterceptor(new eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor(() -> "HonbakoCompatibilityProbe/1"))
        .addInterceptor(new eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor(ignored -> kotlin.Unit.INSTANCE))
        .build();

    public OkHttpClient getClient() { return client; }
    public OkHttpClient getCloudflareClient() { return client; }
    public String defaultUserAgentProvider() { return "HonbakoCompatibilityProbe/1"; }
    public void close() {
        client.connectionPool().evictAll();
        client.dispatcher().executorService().shutdownNow();
    }
}

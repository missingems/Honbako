package eu.kanade.tachiyomi.network.interceptor;

import java.io.IOException;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import okhttp3.Interceptor;
import okhttp3.Response;

/**
 * Required interceptor slot for the local host probe. It performs no challenge
 * handling and refuses non-loopback requests rather than implying support.
 */
public final class CloudflareInterceptor implements Interceptor {
    public CloudflareInterceptor(Function1<? super String, Unit> ignored) {}
    @Override public Response intercept(Chain chain) throws IOException {
        String host = chain.request().url().host();
        if (!host.equals("127.0.0.1") && !host.equals("localhost") && !host.equals("::1")) {
            throw new IOException("This experimental host permits only controlled loopback requests");
        }
        return chain.proceed(chain.request());
    }
}

package com.missingems.honbako.fixture;

import eu.kanade.tachiyomi.source.online.HttpSource;
import eu.kanade.tachiyomi.source.model.Page;
import java.nio.charset.StandardCharsets;
import kotlin.coroutines.Continuation;
import okhttp3.*;

/**
 * Original test source using the real HttpSource API. It proves lazy resolution,
 * source headers and the source client hook; it is not a published provider.
 */
public final class BridgeFixtureSource extends HttpSource {
    static { System.setProperty("honbako.fixture.initialized", "yes"); }
    @Override public String getName() { return "Honbako Original Fixture"; }
    @Override public String getLang() { return "en"; }
    @Override public long getId() { return 9007199254740993L; }
    @Override public String getBaseUrl() { return "http://127.0.0.1"; }
    @Override public boolean getSupportsLatest() { return false; }
    @Override protected Headers.Builder headersBuilder() {
        return super.headersBuilder().add("X-Honbako-Source", "original-fixture");
    }
    @Override public OkHttpClient getClient() {
        return super.getClient().newBuilder().addInterceptor(chain -> chain.proceed(chain.request().newBuilder()
            .addHeader("X-Honbako-Client", "extension-client-hook").build())).build();
    }
    @Override protected Request imageRequest(Page page) {
        return super.imageRequest(page).newBuilder().addHeader("X-Honbako-Page", "extension-image-request-hook").build();
    }
    @Override public Object getImageUrl(Page page, Continuation<? super String> continuation) {
        try (Response response = getClient().newCall(new Request.Builder().url(page.getUrl()).headers(getHeaders()).build()).execute()) {
            if (!response.isSuccessful() || response.body() == null) throw new IllegalStateException("Resolver failed");
            byte[] bytes = response.body().byteStream().readNBytes(8193);
            if (bytes.length > 8192) throw new IllegalStateException("Resolver URL exceeds test limit");
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (java.io.IOException error) { throw new java.io.UncheckedIOException(error); }
    }
}

package com.missingems.honbako.runtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** First-party host test driver; never included in the production bridge JAR. */
public final class BridgeV2Host {
    public static void main(String[] args) throws Exception {
        ObjectMapper json = new ObjectMapper();
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            for (String line; (line = input.readLine()) != null;) {
                try {
                    var wrapper = json.readTree(line);
                    if (wrapper.has("property")) {
                        System.out.println(json.writeValueAsString(Collections.singletonMap("value", System.getProperty(wrapper.get("property").asText()))));
                    } else if (wrapper.has("preference")) {
                        var field = ExtensionBridge.class.getDeclaredField("APPLICATION");
                        field.setAccessible(true);
                        android.app.Application application = (android.app.Application) field.get(null);
                        var specification = wrapper.get("preference");
                        var preferences = application.getSharedPreferences(specification.get("namespace").asText(), 0);
                        if (specification.has("put")) preferences.edit().putString(specification.get("key").asText(), specification.get("put").asText()).commit();
                        System.out.println(json.writeValueAsString(Map.of("value", preferences.getString(specification.get("key").asText(), "missing"))));
                    } else if (wrapper.has("binary")) {
                        ExtensionBridge.ImageResult image = ExtensionBridge.image(wrapper.get("binary").toString());
                        String actual = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image.data));
                        System.out.println(json.writeValueAsString(Map.of("ok", true, "result", Map.of(
                            "bytes", image.data.length, "sha256", image.sha256, "independentlyComputedSHA256", actual,
                            "mediaType", image.mediaType == null ? "" : image.mediaType, "binaryBoundary", true))));
                    } else {
                        System.out.println(ExtensionBridge.execute(wrapper.has("raw") ? wrapper.get("raw").asText() : wrapper.toString()));
                    }
                } catch (Throwable error) {
                    System.out.println(json.writeValueAsString(Map.of("ok", false, "errorType", error.getClass().getName(),
                        "error", String.valueOf(error.getMessage()))));
                }
                System.out.flush();
            }
        } finally { ExtensionBridge.close(); }
        System.exit(0);
    }
}

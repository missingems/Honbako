package com.missingems.honbako.runtime;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.StreamReadConstraints;
import eu.kanade.tachiyomi.network.NetworkHelper;
import eu.kanade.tachiyomi.source.Source;
import eu.kanade.tachiyomi.source.SourceFactory;
import eu.kanade.tachiyomi.source.model.*;
import eu.kanade.tachiyomi.source.online.HttpSource;
import java.io.*;
import java.lang.reflect.*;
import java.net.URL;
import java.net.URLClassLoader;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Function;
import java.util.zip.ZipFile;
import javax.xml.parsers.DocumentBuilderFactory;
import kotlin.ResultKt;
import kotlin.coroutines.*;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import kotlinx.serialization.json.Json;
import org.w3c.dom.Element;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.InjektRegistrar;
import uy.kohesive.injekt.api.InjektScope;

/**
 * Experimental JSON boundary around an actual, unmodified Mihon extension JAR.
 * Dependencies are supplied from a pinned reference runtime on the test host.
 * This class does not launch Suwayomi, a server, or a substitute native source.
 */
public final class ExtensionBridge {
    public static final int MAX_IMAGE_BYTES = 32 * 1024 * 1024;
    public static final int MAX_JSON_BYTES = 8 * 1024 * 1024;
    public static final int MAX_REQUEST_BYTES = 5 * 1024 * 1024;
    private static final int MAX_MANIFEST_BYTES = 1024 * 1024;
    private static final String SUPPORTED_LIBRARY = "1.6";
    private static final ObjectMapper JSON = jsonMapper();
    private static final Map<String, Loaded> LOADED = new LinkedHashMap<>(16, .75f, true);
    private static final ProbeApplication APPLICATION = new ProbeApplication();
    private static final NetworkHelper NETWORK = new NetworkHelper();
    private static boolean initialized;

    private static ObjectMapper jsonMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
        mapper.enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
        mapper.getFactory().setStreamReadConstraints(StreamReadConstraints.builder()
            .maxNestingDepth(16).maxStringLength(1024 * 1024).maxNameLength(1024)
            .maxNumberLength(32).maxDocumentLength(MAX_REQUEST_BYTES).maxTokenCount(100_000).build());
        return mapper;
    }

    private static synchronized void initialize() {
        if (initialized) return;
        InjektRegistrar registrar = (InjektRegistrar) Proxy.newProxyInstance(
            ExtensionBridge.class.getClassLoader(), new Class<?>[]{InjektRegistrar.class}, (proxy, method, args) -> {
                if (method.getName().equals("toString")) return "HonbakoProbeServices";
                if (method.getName().equals("hashCode")) return System.identityHashCode(proxy);
                if (method.getName().equals("equals")) return proxy == args[0];
                Type type = args == null || args.length == 0 ? null : (Type) args[0];
                if (type instanceof ParameterizedType) type = ((ParameterizedType) type).getRawType();
                Object value = type == Application.class || type == Context.class ? APPLICATION
                    : type == NetworkHelper.class ? NETWORK : type == Json.class ? Json.Default : null;
                if (method.getName().equals("hasFactory")) return value != null;
                if (value != null) return value;
                if (method.getName().contains("OrNull")) return null;
                throw new IllegalStateException("Unsupported experimental host service: " + type);
            });
        InjektKt.setInjekt(new InjektScope(registrar));
        initialized = true;
    }

    /** One request and one response string; also callable through JNI. */
    public static synchronized String execute(String input) {
        try {
            initialize();
            Map<String, Object> request = parseRequest(input);
            Loaded loaded = prepare(request);
            String operation = required(request, "operation");
            if (operation.equals("discover")) {
                List<Object> sources = new ArrayList<>();
                for (Source source : loaded.sources) sources.add(source(source));
                return success(Map.of("package", loaded.packageName, "version", loaded.version,
                    "entryClass", loaded.entryClass, "extensionLibrary", loaded.extensionLibrary,
                    "packageSHA256", loaded.sha256, "sources", sources));
            }
            String sourceId = required(request, "sourceId");
            Source source = loaded.sources.stream().filter(s -> Long.toString(s.getId()).equals(sourceId))
                .findFirst().orElseThrow(() -> new IllegalArgumentException("Unknown sourceId"));
            switch (operation) {
                case "search": {
                    String query = bounded(string(request.get("query"), ""), 16_384, "query");
                    int page = integer(request.getOrDefault("page", 1), 1, Integer.MAX_VALUE, "page");
                    // A header is a valid non-query filter. It avoids UI-only
                    // asynchronous filter discovery in this controlled probe.
                    FilterList filters = new FilterList(new Filter.Header("Honbako Probe"));
                    MangasPage result = await(c -> source.getSearchManga(page, query, filters, c));
                    limit(result.getMangas().size(), 4096, "search entries");
                    List<Object> entries = new ArrayList<>();
                    for (SManga manga : result.getMangas()) entries.add(manga(manga));
                    return success(Map.of("entries", entries, "hasNextPage", result.getHasNextPage()));
                }
                case "details":
                case "chapters": {
                    SManga manga = makeManga(map(request.get("manga")));
                    boolean details = operation.equals("details");
                    SMangaUpdate result = await(c -> source.getMangaUpdate(manga, Collections.emptyList(), details, !details, c));
                    limit(result.getChapters().size(), 32_000, "chapters");
                    List<Object> chapters = new ArrayList<>();
                    for (SChapter chapter : result.getChapters()) chapters.add(chapter(chapter));
                    return success(Map.of("manga", manga(result.getManga()), "chapters", chapters));
                }
                case "pages": {
                    Map<String, Object> record = map(request.get("chapter"));
                    SChapter chapter = SChapter.Companion.create();
                    chapter.setUrl(key(required(record, "url")));
                    chapter.setName(bounded(string(record.get("name"), "Chapter"), 16_384, "chapter name"));
                    List<? extends Page> result = await(c -> source.getPageList(chapter, c));
                    limit(result.size(), 4096, "pages");
                    List<Object> pages = new ArrayList<>();
                    for (Page page : result) pages.add(fields("index", page.getIndex(), "url", page.getUrl(), "imageUrl", page.getImageUrl()));
                    return success(Map.of("pages", pages));
                }
                case "image":
                case "cover": {
                    ImageResult image = fetchImage(request, source);
                    boolean includeData = Boolean.TRUE.equals(request.get("includeData"));
                    // The binary JNI method supports the full image limit.
                    // Refuse large legacy JSON images before allocating base64.
                    if (includeData && image.data.length > (MAX_JSON_BYTES - 4096) / 4 * 3)
                        throw new IOException("Image requires the binary JNI boundary");
                    return success(fields("bytes", image.data.length, "sha256", image.sha256, "mediaType", image.mediaType,
                        "dataBase64", includeData ? Base64.getEncoder().encodeToString(image.data) : null));
                }
                default: throw new IllegalArgumentException("Unsupported operation: " + operation);
            }
        } catch (Throwable error) {
            while (error instanceof InvocationTargetException && error.getCause() != null) error = error.getCause();
            try { return encode(fields("ok", false, "errorType", error.getClass().getName(),
                "error", clipped(error.getMessage(), 1024))); }
            catch (Exception encodingError) { return "{\"ok\":false,\"error\":\"Response encoding failed\"}"; }
        }
    }

    private static Loaded load(String path, String scope, Map<String, Object> request) throws Exception {
        Path file = Paths.get(path).toAbsolutePath().normalize();
        if (Files.isSymbolicLink(file) || !Files.isRegularFile(file) || !file.toString().endsWith(".jar")
                || Files.size(file) <= 0 || Files.size(file) > MAX_IMAGE_BYTES) throw new IllegalArgumentException("A bounded local extension JAR is required");
        String sha256;
        try (InputStream bytes = Files.newInputStream(file)) { sha256 = hash(readBounded(bytes, Files.size(file), MAX_IMAGE_BYTES, "Package")); }
        expected(request, "packageSHA256", sha256);
        String cacheKey = file + ":" + sha256 + ":" + scope;
        if (LOADED.containsKey(cacheKey)) {
            Loaded cached = LOADED.get(cacheKey);
            expected(request, "packageName", cached.packageName);
            expected(request, "versionName", cached.version);
            expected(request, "extensionLibrary", cached.extensionLibrary);
            return cached;
        }
        DocumentBuilderFactory parser = DocumentBuilderFactory.newInstance();
        parser.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        parser.setFeature("http://xml.org/sax/features/external-general-entities", false);
        parser.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        parser.setNamespaceAware(true);
        parser.setXIncludeAware(false);
        parser.setExpandEntityReferences(false);
        String namespace = "http://schemas.android.com/apk/res/android";
        String pkg, version, entry = null, library = null;
        try (ZipFile jar = new ZipFile(file.toFile())) {
            var manifest = jar.getEntry("AndroidManifest.xml");
            if (manifest == null || manifest.getSize() > MAX_MANIFEST_BYTES) throw new IllegalArgumentException("Missing or oversized extension manifest");
            try (InputStream xml = jar.getInputStream(manifest)) {
                byte[] boundedXML = readBounded(xml, manifest.getSize(), MAX_MANIFEST_BYTES, "Manifest");
                Element root = parser.newDocumentBuilder().parse(new ByteArrayInputStream(boundedXML)).getDocumentElement();
                pkg = root.getAttribute("package"); version = root.getAttributeNS(namespace, "versionName");
                var metadata = root.getElementsByTagName("meta-data");
                for (int i = 0; i < metadata.getLength(); i++) {
                    Element item = (Element) metadata.item(i);
                    if (item.getAttributeNS(namespace, "name").equals("tachiyomi.extension.class")) entry = item.getAttributeNS(namespace, "value");
                    if (item.getAttributeNS(namespace, "name").equals("tachiyomix.extensionLib")) library = item.getAttributeNS(namespace, "value");
                }
            }
        }
        if (entry == null || entry.isBlank()) throw new IllegalArgumentException("Missing extension entry class");
        if (!SUPPORTED_LIBRARY.equals(library)) throw new IllegalArgumentException("Unsupported extension library: " + library);
        expected(request, "packageName", pkg);
        expected(request, "versionName", version);
        expected(request, "extensionLibrary", library);
        bounded(pkg, 512, "package name"); bounded(version, 512, "version"); bounded(entry, 1024, "entry class");
        if (entry.startsWith(".")) entry = pkg + entry;
        URLClassLoader loader = new URLClassLoader(new URL[]{file.toUri().toURL()}, ExtensionBridge.class.getClassLoader());
        Object instance = Class.forName(entry, true, loader).getDeclaredConstructor().newInstance();
        List<? extends Source> sources = instance instanceof SourceFactory ? ((SourceFactory) instance).createSources()
            : instance instanceof Source ? List.of((Source) instance) : Collections.emptyList();
        if (sources.isEmpty()) throw new IllegalArgumentException("Extension exposes no source");
        limit(sources.size(), 1024, "sources");
        Loaded loaded = new Loaded(pkg, version, entry, library, sha256, scope, sources, loader);
        LOADED.put(cacheKey, loaded);
        if (LOADED.size() > 16) {
            String oldest = LOADED.keySet().iterator().next();
            Loaded evicted = LOADED.remove(oldest);
            evicted.loader.close();
            APPLICATION.forget(evicted.scope);
        }
        return loaded;
    }

    private static <T> T await(Function<Continuation<? super T>, Object> operation) throws Exception {
        CompletableFuture<T> future = new CompletableFuture<>();
        Continuation<T> continuation = new Continuation<>() {
            public CoroutineContext getContext() { return EmptyCoroutineContext.INSTANCE; }
            @SuppressWarnings("unchecked") public void resumeWith(Object result) {
                try { ResultKt.throwOnFailure(result); future.complete((T) result); }
                catch (Throwable failure) { future.completeExceptionally(failure); }
            }
        };
        Object result = operation.apply(continuation);
        if (result != IntrinsicsKt.getCOROUTINE_SUSPENDED()) { @SuppressWarnings("unchecked") T immediate = (T) result; return immediate; }
        return future.get(35, TimeUnit.SECONDS);
    }

    /** Binary boundary for JNI. No base64 or JSON image copies are allocated. */
    public static synchronized ImageResult image(String input) throws Exception {
        initialize();
        Map<String, Object> request = parseRequest(input);
        String operation = required(request, "operation");
        if (!operation.equals("image") && !operation.equals("cover")) throw new IllegalArgumentException("An image or cover operation is required");
        Loaded loaded = prepare(request);
        String id = required(request, "sourceId");
        Source source = loaded.sources.stream().filter(item -> Long.toString(item.getId()).equals(id)).findFirst()
            .orElseThrow(() -> new IllegalArgumentException("Unknown sourceId"));
        return fetchImage(request, source);
    }

    public static byte[] imageBytes(String input) throws Exception { return image(input).data; }

    public static final class ImageResult {
        public final byte[] data;
        public final String mediaType;
        public final String sha256;
        private ImageResult(byte[] data, String mediaType) throws Exception {
            this.data = data;
            this.mediaType = mediaType;
            this.sha256 = hash(data);
        }
    }

    private static ImageResult fetchImage(Map<String, Object> request, Source source) throws Exception {
        if (!(source instanceof HttpSource)) throw new IllegalArgumentException("This source has no HTTP image service");
        HttpSource http = (HttpSource) source;
        okhttp3.Response response;
        if (required(request, "operation").equals("cover")) {
            // Covers use the source's headers/client, including authentication
            // and source-installed interceptors. They are not fabricated pages.
            String url = absoluteURL(required(request, "url"));
            okhttp3.Request cover = new okhttp3.Request.Builder().url(url).headers(http.getHeaders()).get().build();
            response = http.getClient().newCall(cover).execute();
        } else {
            Map<String, Object> record = map(request.get("page"));
            String pageURL = string(record.get("url"), "");
            if (!pageURL.isEmpty()) key(pageURL);
            String imageURL = optionalString(record.get("imageUrl"));
            Page page = new Page(integer(record.getOrDefault("index", 0), 0, Integer.MAX_VALUE, "page index"), pageURL, imageURL, null);
            if (imageURL == null || imageURL.isEmpty()) {
                if (pageURL.isEmpty()) throw new IllegalArgumentException("An image URL or resolver page URL is required");
                // This is the extension's actual lazy resolver, followed by its
                // actual getImage/imageRequest path and response interceptors.
                String resolved = await(c -> http.getImageUrl(page, c));
                page.setImageUrl(absoluteURL(resolved));
            } else { page.setImageUrl(absoluteURL(imageURL)); }
            response = await(c -> http.getImage(page, c));
        }
        try (response) {
            if (!response.isSuccessful() || response.body() == null) throw new IOException("Image response failed: " + response.code());
            String type = response.header("Content-Type");
            if (type != null) {
                bounded(type, 256, "media type");
                String normalized = type.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
                if (!(normalized.startsWith("image/") || normalized.equals("application/octet-stream"))) throw new IOException("Non-image response type");
            }
            byte[] bytes = readBounded(response.body().byteStream(), response.body().contentLength(), MAX_IMAGE_BYTES, "Image");
            if (bytes.length == 0) throw new IOException("Empty image response");
            return new ImageResult(bytes, type);
        }
    }

    private static Map<String, Object> parseRequest(String input) throws Exception {
        if (input == null || input.length() > MAX_REQUEST_BYTES || input.getBytes(StandardCharsets.UTF_8).length > MAX_REQUEST_BYTES)
            throw new IllegalArgumentException("Request exceeds byte limit");
        Map<String, Object> request = JSON.readValue(input, new TypeReference<Map<String, Object>>(){});
        if (request == null || request.size() > 24) throw new IllegalArgumentException("Invalid request object");
        bounded(required(request, "operation"), 32, "operation");
        bounded(required(request, "extensionPath"), 8192, "extension path");
        Object sourceID = request.get("sourceId");
        if (sourceID != null && (!(sourceID instanceof String) || !Long.toString(Long.parseLong((String) sourceID)).equals(sourceID)))
            throw new IllegalArgumentException("Invalid exact source ID");
        return request;
    }

    private static Loaded prepare(Map<String, Object> request) throws Exception {
        Map<String, Object> preferences = map(request.get("preferences"));
        limit(preferences.size(), 256, "preferences");
        Map<String, Object> ordered = new TreeMap<>();
        int size = 0;
        for (Map.Entry<String, Object> entry : preferences.entrySet()) {
            bounded(entry.getKey(), 1024, "preference key");
            if (!(entry.getValue() instanceof String)) throw new IllegalArgumentException("Only string preferences are supported");
            String value = bounded((String) entry.getValue(), 16_384, "preference value");
            size += entry.getKey().getBytes(StandardCharsets.UTF_8).length + value.getBytes(StandardCharsets.UTF_8).length;
            if (size > 4 * 1024 * 1024) throw new IllegalArgumentException("Preferences exceed byte limit");
            ordered.put(entry.getKey(), value);
        }
        String path = Paths.get(required(request, "extensionPath")).toAbsolutePath().normalize().toString();
        String source = string(request.get("sourceId"), "discovery");
        String scope = hash((path + "\n" + source + "\n" + encode(ordered)).getBytes(StandardCharsets.UTF_8));
        APPLICATION.configure(scope, ordered);
        return load(path, scope, request);
    }

    private static byte[] readBounded(InputStream input, long length, int maximum, String kind) throws IOException {
        if (length > maximum) throw new IOException(kind + " exceeds " + maximum + "-byte limit");
        if (length >= 0) {
            byte[] bytes = new byte[(int) length];
            int offset = 0;
            while (offset < bytes.length) {
                int count = input.read(bytes, offset, bytes.length - offset);
                if (count < 0) throw new IOException("Truncated " + kind.toLowerCase(Locale.ROOT));
                if (count == 0) continue;
                offset += count;
            }
            if (input.read() != -1) throw new IOException(kind + " length mismatch or byte limit exceeded");
            return bytes;
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream(Math.min(maximum, 64 * 1024));
        byte[] buffer = new byte[64 * 1024];
        int total = 0;
        while (true) {
            int count = input.read(buffer, 0, Math.min(buffer.length, maximum - total + 1));
            if (count < 0) break;
            if (count > maximum - total) throw new IOException(kind + " exceeds " + maximum + "-byte limit");
            total += count;
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static void expected(Map<String, Object> request, String name, String actual) {
        if (request.containsKey(name) && !Objects.equals(request.get(name), actual)) throw new IllegalArgumentException("Package identity mismatch: " + name);
    }

    private static String hash(byte[] data) throws Exception { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)); }
    private static void limit(int count, int maximum, String name) { if (count > maximum) throw new IllegalArgumentException("Too many " + name); }
    private static int integer(Object value, int minimum, int maximum, String name) {
        if (!(value instanceof Number) || value instanceof Float || value instanceof Double) throw new IllegalArgumentException("Invalid " + name);
        long number = ((Number) value).longValue();
        if (number < minimum || number > maximum) throw new IllegalArgumentException("Invalid " + name);
        return (int) number;
    }
    private static String optionalString(Object value) {
        if (value == null) return null;
        if (!(value instanceof String)) throw new IllegalArgumentException("Expected a string");
        return (String) value;
    }
    private static String bounded(String value, int maximum, String name) {
        if (value == null || value.length() > maximum || value.getBytes(StandardCharsets.UTF_8).length > maximum)
            throw new IllegalArgumentException(name + " exceeds byte limit");
        return value;
    }
    private static String clipped(String value, int maximum) { return value == null ? "Operation failed" : value.substring(0, Math.min(value.length(), maximum)); }
    private static String key(String value) {
        bounded(value, 16_384, "source key");
        if (value.isEmpty() || value.contains("\\") || value.codePoints().anyMatch(c -> c < 0x20 || c == 0x7f)) throw new IllegalArgumentException("Invalid source key");
        try {
            URI uri = URI.create(value);
            if (uri.getRawUserInfo() != null || (uri.getScheme() != null && !List.of("http", "https").contains(uri.getScheme().toLowerCase(Locale.ROOT))))
                throw new IllegalArgumentException("Invalid source URL");
        } catch (IllegalArgumentException error) { throw new IllegalArgumentException("Invalid source key"); }
        return value;
    }
    private static String absoluteURL(String value) {
        key(value);
        URI uri = URI.create(value);
        if (uri.getScheme() == null || uri.getHost() == null || uri.getHost().isBlank()) throw new IllegalArgumentException("An absolute HTTP image URL is required");
        return value;
    }

    private static String encode(Object value) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        OutputStream bounded = new FilterOutputStream(bytes) {
            int count;
            @Override public void write(int value) throws IOException { if (count == MAX_JSON_BYTES) throw new IOException("JSON response exceeds byte limit"); out.write(value); count++; }
            @Override public void write(byte[] data, int start, int length) throws IOException {
                if (length > MAX_JSON_BYTES - count) throw new IOException("JSON response exceeds byte limit");
                out.write(data, start, length); count += length;
            }
        };
        JSON.writeValue(bounded, value);
        return bytes.toString(StandardCharsets.UTF_8);
    }

    private static Map<String, Object> source(Source value) {
        return fields("id", Long.toString(value.getId()), "name", bounded(value.getName(), 16_384, "source name"),
            "language", bounded(value.getLang(), 64, "source language"), "supportsLatest", value.getSupportsLatest());
    }
    private static Map<String, Object> manga(SManga value) {
        return fields("url", key(value.getUrl()), "title", bounded(value.getTitle(), 16_384, "manga title"),
            "cover", limitedNullable(value.getThumbnail_url(), 16_384), "author", limitedNullable(value.getAuthor(), 16_384),
            "artist", limitedNullable(value.getArtist(), 16_384), "description", limitedNullable(value.getDescription(), 512 * 1024), "status", value.getStatus());
    }
    private static SManga makeManga(Map<String, Object> record) {
        SManga value = SManga.Companion.create(); value.setUrl(key(required(record, "url")));
        value.setTitle(bounded(string(record.get("title"), "Manga"), 16_384, "manga title")); return value;
    }
    private static Map<String, Object> chapter(SChapter value) {
        return fields("url", key(value.getUrl()), "name", bounded(value.getName(), 16_384, "chapter name"),
            "number", value.getChapter_number(), "uploadedAt", value.getDate_upload(), "scanlator", limitedNullable(value.getScanlator(), 16_384));
    }
    private static Map<String, Object> fields(Object... pairs) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) result.put((String) pairs[i], pairs[i + 1]);
        return result;
    }
    @SuppressWarnings("unchecked") private static Map<String, Object> map(Object value) { return value instanceof Map ? (Map<String, Object>) value : Collections.emptyMap(); }
    private static String string(Object value, String fallback) { return value instanceof String ? (String) value : fallback; }
    private static int number(Object value, int fallback) { return value instanceof Number ? ((Number) value).intValue() : fallback; }
    private static String required(Map<String, Object> values, String name) {
        String value = string(values.get(name), ""); if (value.isBlank()) throw new IllegalArgumentException("Missing " + name); return value;
    }
    private static String limitedNullable(String value, int maximum) { return value == null ? null : bounded(value, maximum, "source text"); }
    private static String success(Object value) throws IOException { return encode(Map.of("ok", true, "result", value)); }

    public static void main(String[] args) throws Exception {
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            for (String line; (line = input.readLine()) != null;) { System.out.println(execute(line)); System.out.flush(); }
        }
        // The host probe owns its process. JNI clients must call execute instead.
        System.exit(0);
    }

    /** Dispose the one-shot experimental session without exiting an embedding process. */
    public static synchronized void close() {
        for (Loaded loaded : LOADED.values()) try { loaded.loader.close(); } catch (IOException ignored) {}
        LOADED.clear();
        NETWORK.close();
    }

    private record Loaded(String packageName, String version, String entryClass, String extensionLibrary, String sha256, String scope,
                          List<? extends Source> sources, URLClassLoader loader) {}

    /** In-memory preferences isolate the reference probe from all user data. */
    private static final class ProbeApplication extends Application {
        private final Map<String, Map<String, Map<String, Object>>> scoped = new ConcurrentHashMap<>();
        private volatile String activeScope;
        private volatile Map<String, Object> defaults = Map.of();
        void configure(String scope, Map<String, Object> input) {
            activeScope = scope;
            defaults = Map.copyOf(input);
        }
        void forget(String scope) { scoped.remove(scope); }
        @Override public Context getApplicationContext() { return this; }
        @Override public String getPackageName() { return "com.missingems.honbaku.compatibilityprobe"; }
        @Override public File getFilesDir() { return new File(System.getProperty("java.io.tmpdir"), "honbako-compatibility-probe"); }
        @Override public File getCacheDir() { return getFilesDir(); }
        @Override public SharedPreferences getSharedPreferences(String name, int mode) {
            bounded(name, 1024, "preference namespace");
            String scope = activeScope;
            if (scope == null) throw new IllegalStateException("No active extension preference scope");
            Map<String, Object> seed = defaults;
            Map<String, Map<String, Object>> namespaces = scoped.computeIfAbsent(scope, ignored -> new ConcurrentHashMap<>());
            if (!namespaces.containsKey(name) && namespaces.size() >= 64) throw new IllegalStateException("Too many preference namespaces");
            Map<String, Object> values = namespaces.computeIfAbsent(name, ignored -> new ConcurrentHashMap<>(seed));
            return (SharedPreferences) Proxy.newProxyInstance(getClass().getClassLoader(), new Class<?>[]{SharedPreferences.class}, (proxy, method, args) -> {
                String m = method.getName();
                if (m.equals("getAll")) return new HashMap<>(values);
                if (m.equals("contains")) return values.containsKey(args[0]);
                if (m.startsWith("get")) return values.getOrDefault(args[0], args[1]);
                if (m.equals("edit")) return Proxy.newProxyInstance(getClass().getClassLoader(), new Class<?>[]{SharedPreferences.Editor.class}, (editor, action, params) -> {
                    String a = action.getName();
                    if (a.startsWith("put")) { if (params[1] == null) values.remove(params[0]); else values.put((String) params[0], params[1]); return editor; }
                    if (a.equals("remove")) { values.remove(params[0]); return editor; }
                    if (a.equals("clear")) { values.clear(); return editor; }
                    if (a.equals("commit")) return true;
                    return null;
                });
                return null;
            });
        }
    }
}

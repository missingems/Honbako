package com.missingems.honbako.runtime;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** One-shot, self-contained real-extension proof, callable from JNI. */
public final class KomgaDeviceProbe {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final String PACKAGE = "tachiyomi-all.komga-v1.6.74.jar";
    private static final String EXPECTED = "9f1b4a05113f33d4de7f5177dded79419ef33e5d91c3ce38a3e55b609c522013";
    private static Fixture retainedFixture;

    public static synchronized String run(String bundleRoot) {
        List<Object> operations = new ArrayList<>();
        String phase = "package-verification";
        try {
            Path root = Paths.get(bundleRoot).toAbsolutePath().normalize();
            Path extension = root.resolve(PACKAGE);
            require(hash(Files.readAllBytes(extension)).equals(EXPECTED), "Published extension checksum mismatch");
            phase = "local-fixture";
            if (retainedFixture != null) throw new IllegalStateException("A diagnostic fixture is already retained");
            Fixture fixture = new Fixture(root.resolve("fixture"));
            try {
                Map<String, Object> common = Map.of("extensionPath", extension.toString(),
                    "preferences", Map.of("Address", "http://127.0.0.1:" + fixture.port()));
                phase = "discovery";
                Map<String, Object> discovered = call(common, operations, "discover");
                require(discovered.get("version").equals("1.6.74"), "Unexpected extension version");
                List<Map<String, Object>> sources = records(discovered.get("sources"));
                require(sources.size() == 3, "Expected three extension factory sources");
                String sourceId = (String) sources.get(0).get("id");
                require(sourceId.equals("4508733312114627536"), "Source ID lost precision or changed");
                phase = "search";
                Map<String, Object> found = call(common, operations, "search", "sourceId", sourceId, "query", "Your First");
                List<Map<String, Object>> entries = records(found.get("entries"));
                require(entries.size() == 1 && Boolean.FALSE.equals(found.get("hasNextPage")), "Search metadata mismatch");
                Map<String, Object> manga = entries.get(0);
                require("Your First Chapter".equals(manga.get("title")) && "Honbako".equals(manga.get("author")), "Source metadata mismatch");
                phase = "details";
                Map<String, Object> detail = call(common, operations, "details", "sourceId", sourceId, "manga", manga);
                require(((Number) record(detail.get("manga")).get("status")).intValue() == 2, "Completed status not preserved");
                phase = "chapters";
                List<Map<String, Object>> chapters = records(call(common, operations, "chapters", "sourceId", sourceId, "manga", manga).get("chapters"));
                require(chapters.size() == 1 && ((Number) chapters.get(0).get("number")).intValue() == 1, "Chapter metadata mismatch");
                require(((Number) chapters.get(0).get("uploadedAt")).longValue() > 0, "Chapter release date missing");
                phase = "pages";
                List<Map<String, Object>> pages = records(call(common, operations, "pages", "sourceId", sourceId, "chapter", chapters.get(0)).get("pages"));
                require(pages.size() == 3, "Expected three original pages");
                List<String> imageHashes = new ArrayList<>();
                for (int index = 0; index < 3; index++) {
                    phase = "image-" + (index + 1);
                    Map<String, Object> page = pages.get(index);
                    require(((Number) page.get("index")).intValue() == index + 1, "Page order changed");
                    Map<String, Object> image = call(common, operations, "image", "sourceId", sourceId, "page", page);
                    String actual = (String) image.get("sha256");
                    require(actual.equals(hash(fixture.pages.get(index))), "Original page bytes/order changed");
                    require(((Number) image.get("bytes")).intValue() == fixture.pages.get(index).length, "Incomplete image response");
                    imageHashes.add(actual);
                }
                require(new HashSet<>(imageHashes).size() == 3, "Page previews repeated the same image");
                phase = "empty-search";
                Map<String, Object> empty = call(common, operations, "search", "sourceId", sourceId, "query", "No Such Original Book");
                require(records(empty.get("entries")).isEmpty(), "Empty query result was not preserved");
                Map<String, Object> result = new LinkedHashMap<>(Map.of("ok", true, "phase", "complete", "extensionVersion", "1.6.74",
                    "packageSha256", EXPECTED, "sourceIds", sources.stream().map(s -> s.get("id")).toList(),
                    "pageSha256", imageHashes, "operations", operations, "httpRequests", fixture.requestsSnapshot(),
                    "suwayomiServerStarted", false, "network", "in-process loopback fixture"));
                if (Boolean.getBoolean("honbako.probe.keepFixture")) {
                    result.put("fixtureRetained", true);
                    result.put("fixtureBaseURL", "http://127.0.0.1:" + fixture.port());
                    String encoded = JSON.writeValueAsString(result);
                    retainedFixture = fixture;
                    return encoded;
                }
                return JSON.writeValueAsString(result);
            } finally {
                if (retainedFixture != fixture) fixture.close();
            }
        } catch (Throwable failure) {
            failure.printStackTrace(System.err);
            try { return JSON.writeValueAsString(Map.of("ok", false, "phase", phase,
                "errorType", failure.getClass().getName(), "error", String.valueOf(failure.getMessage()), "operations", operations)); }
            catch (Exception ignored) { return "{\"ok\":false,\"error\":\"Proof result encoding failed\"}"; }
        } finally {
            if (retainedFixture == null) ExtensionBridge.close();
        }
    }

    /** Diagnostic opt-in only; the native test must call this in its finally. */
    public static synchronized void closeRetainedFixture() throws Exception {
        Fixture fixture = retainedFixture;
        retainedFixture = null;
        try { if (fixture != null) fixture.close(); }
        finally { ExtensionBridge.close(); }
    }

    private static Map<String, Object> call(Map<String, Object> common, List<Object> operations, String operation, Object... pairs) throws Exception {
        Map<String, Object> request = new LinkedHashMap<>(common);
        request.put("operation", operation);
        for (int i = 0; i < pairs.length; i += 2) request.put((String) pairs[i], pairs[i + 1]);
        Map<String, Object> response = JSON.readValue(ExtensionBridge.execute(JSON.writeValueAsString(request)), new TypeReference<Map<String, Object>>(){});
        operations.add(Map.of("operation", operation, "response", response));
        require(Boolean.TRUE.equals(response.get("ok")), "Extension " + operation + " failed: " + response.get("error"));
        return record(response.get("result"));
    }

    @SuppressWarnings("unchecked") private static Map<String, Object> record(Object value) { return (Map<String, Object>) value; }
    @SuppressWarnings("unchecked") private static List<Map<String, Object>> records(Object value) { return (List<Map<String, Object>>) value; }
    private static void require(boolean condition, String message) { if (!condition) throw new IllegalStateException(message); }
    private static String hash(byte[] data) throws Exception { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)); }

    public static void main(String[] args) { System.out.println(run(args[0])); }

    private static final class Fixture implements AutoCloseable {
        private final ServerSocket socket;
        private final Thread acceptor;
        private final ExecutorService clients = Executors.newFixedThreadPool(4, action -> {
            Thread thread = new Thread(action, "HonbakoProbeHTTPClient"); thread.setDaemon(true); return thread;
        });
        private final List<byte[]> pages = new ArrayList<>();
        private final byte[] cover;
        private final List<String> requests = Collections.synchronizedList(new ArrayList<>());
        private final Map<String, Object> series;
        private final Map<String, Object> chapter;

        Fixture(Path root) throws Exception {
            for (int index = 1; index <= 3; index++) pages.add(Files.readAllBytes(root.resolve("page-" + index + ".png")));
            cover = Files.readAllBytes(root.resolve("cover.png"));
            Map<String, Object> data = JSON.readValue(DATA, new TypeReference<Map<String, Object>>(){});
            series = record(data.get("series")); chapter = record(data.get("chapter"));
            socket = new ServerSocket();
            socket.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0));
            socket.setSoTimeout(1000);
            acceptor = new Thread(() -> {
                while (!socket.isClosed()) {
                    try {
                        Socket client = socket.accept();
                        clients.submit(() -> respond(client));
                    } catch (SocketTimeoutException ignored) {
                    } catch (IOException | RejectedExecutionException failure) {
                        if (!socket.isClosed()) failure.printStackTrace(System.err);
                        return;
                    }
                }
            }, "HonbakoProbeHTTPAcceptor");
            acceptor.setDaemon(true); acceptor.start();
        }

        int port() { return socket.getLocalPort(); }
        List<String> requestsSnapshot() { synchronized (requests) { return List.copyOf(requests); } }

        private void respond(Socket client) {
            try (client) {
                client.setSoTimeout(10000);
                InputStream input = client.getInputStream();
                String first = line(input);
                require(first != null && first.startsWith("GET "), "Only GET is supported by the proof fixture");
                String target = first.split(" ", 3)[1];
                for (int count = 0; count < 64; count++) {
                    String header = line(input);
                    if (header == null || header.isEmpty()) break;
                    if (count == 63) throw new IOException("Too many fixture request headers");
                }
                require(requests.size() < 64, "Fixture request limit exceeded");
                requests.add(target);
                URI uri = URI.create(target);
                String path = uri.getPath();
                Object body = null;
                String type = "application/json";
                if (path.equals("/api/v1/series")) {
                    String query = "";
                    if (uri.getRawQuery() != null) for (String item : uri.getRawQuery().split("&")) {
                        String[] pair = item.split("=", 2);
                        if (pair[0].equals("search")) query = pair.length == 2 ? URLDecoder.decode(pair[1], StandardCharsets.UTF_8) : "";
                    }
                    body = collection("Your First Chapter".toLowerCase(Locale.ROOT).contains(query.toLowerCase(Locale.ROOT)) ? List.of(series) : List.of());
                } else if (path.equals("/api/v1/series/honbako-original")) body = series;
                else if (path.equals("/api/v1/series/honbako-original/books")) body = collection(List.of(chapter));
                else if (path.equals("/api/v1/books/original-1/pages")) body = List.of(
                    Map.of("number", 1, "fileName", "page-1.png", "mediaType", "image/png"),
                    Map.of("number", 2, "fileName", "page-2.png", "mediaType", "image/png"),
                    Map.of("number", 3, "fileName", "page-3.png", "mediaType", "image/png"));
                else if (path.startsWith("/api/v1/books/original-1/pages/")) {
                    int index = Integer.parseInt(path.substring(path.lastIndexOf('/') + 1)) - 1;
                    if (index >= 0 && index < pages.size()) { body = pages.get(index); type = "image/png"; }
                } else if (path.equals("/api/v1/series/honbako-original/thumbnail")) { body = cover; type = "image/png"; }
                int status = body == null ? 404 : 200;
                byte[] bytes = body instanceof byte[] ? (byte[]) body : JSON.writeValueAsBytes(body == null ? Map.of("error", "Unknown fixture path") : body);
                OutputStream output = client.getOutputStream();
                output.write(("HTTP/1.1 " + status + (status == 200 ? " OK" : " Not Found") + "\r\nContent-Type: " + type
                    + "\r\nContent-Length: " + bytes.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                output.write(bytes); output.flush();
            } catch (Throwable failure) {
                if (!socket.isClosed()) failure.printStackTrace(System.err);
            }
        }

        private static String line(InputStream input) throws IOException {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            for (int count = 0; count < 8192; count++) {
                int next = input.read();
                if (next == -1) return buffer.size() == 0 ? null : buffer.toString(StandardCharsets.US_ASCII);
                if (next == '\n') return buffer.toString(StandardCharsets.US_ASCII).replace("\r", "");
                buffer.write(next);
            }
            throw new IOException("Fixture request line too large");
        }

        private static Map<String, Object> collection(List<?> items) {
            return Map.of("content", items, "empty", items.isEmpty(), "first", true, "last", true,
                "number", 0, "numberOfElements", items.size(), "size", 20, "totalElements", items.size(), "totalPages", 1);
        }

        @Override public void close() throws Exception {
            socket.close(); clients.shutdownNow(); acceptor.join(1500); clients.awaitTermination(1500, TimeUnit.MILLISECONDS);
        }
    }

    private static final String DATA = """
        {"series":{"id":"honbako-original","libraryId":"owned-content","name":"Your First Chapter",
        "created":"2026-10-27T00:00:00Z","lastModified":"2026-10-27T00:00:00Z","fileLastModified":"2026-10-27T00:00:00Z","booksCount":1,
        "metadata":{"status":"ENDED","created":"2026-10-27T00:00:00Z","lastModified":"2026-10-27T00:00:00Z",
        "title":"Your First Chapter","titleSort":"Your First Chapter","summary":"Original Honbako compatibility test content.","summaryLock":false,
        "readingDirection":"RIGHT_TO_LEFT","readingDirectionLock":false,"publisher":"Honbako","publisherLock":false,
        "ageRating":null,"ageRatingLock":false,"language":"en","languageLock":false,"genres":[],"genresLock":false,"tags":[],"tagsLock":false,"totalBookCount":1},
        "booksMetadata":{"authors":[{"name":"Honbako","role":"writer"}],"tags":[],"releaseDate":"2026-10-27","summary":"An original story.","summaryNumber":"1",
        "created":"2026-10-27T00:00:00Z","lastModified":"2026-10-27T00:00:00Z"}},
        "chapter":{"id":"original-1","seriesId":"honbako-original","seriesTitle":"Your First Chapter","name":"Your First Chapter","number":1,
        "created":"2026-10-27T00:00:00Z","lastModified":"2026-10-27T00:00:00Z","fileLastModified":"2026-10-27T00:00:00Z","sizeBytes":1,"size":"Original Test Pages",
        "media":{"status":"READY","mediaType":"application/zip","pagesCount":3},
        "metadata":{"title":"Your First Chapter","titleLock":false,"summary":"An original story.","summaryLock":false,"number":"1","numberLock":false,
        "numberSort":1,"numberSortLock":false,"releaseDate":"2026-10-27","releaseDateLock":false,"authors":[{"name":"Honbako","role":"writer"}],"authorsLock":false,"tags":[],"tagsLock":false}}}
        """;
}

package com.missingems.honbako.runtime;

import com.googlecode.d2j.dex.Dex2jar;
import com.googlecode.d2j.reader.MultiDexFileReader;
import com.googlecode.d2j.reader.BaseDexFileReader;
import com.googlecode.d2j.reader.Op;
import com.googlecode.d2j.Method;
import com.googlecode.d2j.node.*;
import com.googlecode.d2j.node.insn.*;
import com.googlecode.d2j.visitors.DexFileVisitor;
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import net.dongliu.apk.parser.ApkFile;
import suwayomi.tachidesk.manga.impl.util.BytecodeEditor;

/**
 * Host-only APK translation experiment using the real Dex2jar library.
 * Translation options follow Suwayomi PackageTools.dex2jar (MPL-2.0):
 * https://github.com/Suwayomi/Suwayomi-Server/blob/master/server/src/main/kotlin/suwayomi/tachidesk/manga/impl/util/PackageTools.kt
 * This does not verify an APK signing block and must not be used as an installer.
 */
public final class ApkConversionProbe {
    public static void main(String[] args) throws Exception {
        Path apk = Paths.get(args[0]).toAbsolutePath();
        Path output = Paths.get(args[1]).toAbsolutePath();
        if (!Files.isRegularFile(apk) || Files.size(apk) > 16 * 1024 * 1024) throw new IllegalArgumentException("Unexpected probe APK");
        if (Files.exists(output)) throw new IllegalArgumentException("Refusing to overwrite an existing converted JAR");
        String manifest;
        try (ApkFile parsed = new ApkFile(apk.toFile())) { manifest = parsed.getManifestXml(); }
        if (manifest == null || manifest.isBlank()) throw new IllegalArgumentException("APK manifest could not be decoded");
        BaksmaliBaseDexExceptionHandler errors = new BaksmaliBaseDexExceptionHandler();
        BaseDexFileReader original = MultiDexFileReader.open(Files.readAllBytes(apk));
        DexFileNode dex = new DexFileNode();
        original.accept(dex);
        int restored = restoreInlinedObjectConstructors(dex);
        BaseDexFileReader normalized = new BaseDexFileReader() {
            public int getDexVersion() { return original.getDexVersion(); }
            public List<String> getClassNames() { return dex.clzs.stream().map(type -> type.className).toList(); }
            public void accept(DexFileVisitor visitor) { dex.accept(visitor); }
            public void accept(DexFileVisitor visitor, int flags) { dex.accept(visitor); }
            public void accept(DexFileVisitor visitor, int index, int flags) { dex.clzs.get(index).accept(visitor); }
        };
        Dex2jar.from(normalized)
            .withExceptionHandler(errors).reUseReg(false).topoLogicalSort()
            .skipDebug(true).optimizeSynchronized(false).printIR(false)
            .noCode(false).skipExceptions(false).dontSanitizeNames(true)
            .computeFrames(true).to(output);
        if (errors.hasException()) {
            errors.dump(output.resolveSibling(output.getFileName() + ".conversion-errors.txt"), new String[0]);
            throw new IllegalStateException("Dex2jar reported a translation error; generated stubs are not accepted");
        }
        BytecodeEditor.INSTANCE.fixAndroidClasses(output);
        Map<String, byte[]> resources = new LinkedHashMap<>();
        try (ZipFile archive = new ZipFile(apk.toFile())) {
            for (ZipEntry item : Collections.list(archive.entries())) {
                String name = item.getName();
                if (item.isDirectory() || name.equals("AndroidManifest.xml") || name.endsWith(".dex")) continue;
                // APK signatures describe the APK's byte layout, not this new
                // unsigned JAR. Never carry signature-looking files across.
                String upper = name.toUpperCase(Locale.ROOT);
                if (upper.startsWith("META-INF/") && (upper.endsWith(".RSA") || upper.endsWith(".DSA")
                    || upper.endsWith(".EC") || upper.endsWith(".SF") || upper.endsWith("MANIFEST.MF"))) continue;
                if (name.startsWith("/") || name.contains("..") || item.getSize() > 8 * 1024 * 1024) throw new IllegalArgumentException("Unsafe APK resource");
                try (var input = archive.getInputStream(item)) { resources.put(name, input.readAllBytes()); }
            }
        }
        resources.put("AndroidManifest.xml", manifest.getBytes(StandardCharsets.UTF_8));
        try (FileSystem archive = FileSystems.newFileSystem(output)) {
            for (Map.Entry<String, byte[]> item : resources.entrySet()) {
                Path target = archive.getPath("/" + item.getKey());
                if (target.getParent() != null) Files.createDirectories(target.getParent());
                Files.write(target, item.getValue());
            }
        }
        System.out.println("Converted actual APK DEX to an unsigned JAR; translation errors: zero; restored R8 constructor calls: "
            + restored + "; signature verification: not performed");
    }

    /**
     * R8 may emit new-instance X followed directly by Object.<init>, with X's
     * empty constructor removed. JVM bytecode needs X.<init> at that call site.
     * Restore that exact allocation type; retain all real methods and field
     * assignments. Never replace an extension method or invent an API result.
     */
    private static int restoreInlinedObjectConstructors(DexFileNode file) {
        Map<String, DexClassNode> types = new HashMap<>();
        for (DexClassNode type : file.clzs) types.put(type.className, type);
        Set<String> restoredTypes = new HashSet<>();
        int count = 0;
        for (DexClassNode owner : file.clzs) {
            if (owner.methods == null) continue;
            for (DexMethodNode method : new ArrayList<>(owner.methods)) {
                if (method.codeNode == null) continue;
                TypeStmtNode allocation = null;
                List<DexStmtNode> code = method.codeNode.stmts;
                for (int index = 0; index < code.size(); index++) {
                    DexStmtNode statement = code.get(index);
                    if (statement instanceof DexLabelStmtNode) continue;
                    if (statement instanceof MethodStmtNode && method.method.getName().equals("<init>")
                            && !owner.superClass.equals("Ljava/lang/Object;")) {
                        MethodStmtNode invocation = (MethodStmtNode) statement;
                        Method target = invocation.method;
                        int parameterRegisters = Arrays.stream(method.method.getParameterTypes())
                            .mapToInt(parameter -> parameter.equals("J") || parameter.equals("D") ? 2 : 1).sum();
                        int thisRegister = method.codeNode.totalRegister - parameterRegisters - 1;
                        if ((statement.op == Op.INVOKE_DIRECT || statement.op == Op.INVOKE_DIRECT_RANGE)
                                && target.getOwner().equals("Ljava/lang/Object;") && target.getName().equals("<init>")
                                && target.getParameterTypes().length == 0 && invocation.args.length == 1
                                && invocation.args[0] == thisRegister
                                && canRestoreConstructor(owner.superClass, types, restoredTypes, new HashSet<>())) {
                            restoreConstructor(owner.superClass, types, restoredTypes);
                            code.set(index, new MethodStmtNode(statement.op, invocation.args,
                                new Method(owner.superClass, "<init>", new String[0], "V")));
                            count++;
                            allocation = null;
                            continue;
                        }
                    }
                    if (statement instanceof TypeStmtNode && statement.op == Op.NEW_INSTANCE) {
                        allocation = (TypeStmtNode) statement;
                        continue;
                    }
                    if (allocation != null && statement instanceof MethodStmtNode) {
                        MethodStmtNode invocation = (MethodStmtNode) statement;
                        Method target = invocation.method;
                        DexClassNode type = types.get(allocation.type);
                        boolean pattern = type != null
                            && !"Ljava/lang/Object;".equals(allocation.type)
                            && (statement.op == Op.INVOKE_DIRECT || statement.op == Op.INVOKE_DIRECT_RANGE)
                            && target.getOwner().equals("Ljava/lang/Object;") && target.getName().equals("<init>")
                            && target.getParameterTypes().length == 0 && invocation.args.length == 1
                            && invocation.args[0] == allocation.a;
                        if (pattern) {
                            // Existing constructors may contain side effects;
                            // this narrow lowering must never invoke those. A
                            // fully erased, local superclass chain can be
                            // restored using only empty constructor delegates.
                            if (canRestoreConstructor(type.className, types, restoredTypes, new HashSet<>())) {
                                restoreConstructor(type.className, types, restoredTypes);
                                Method constructor = new Method(type.className, "<init>", new String[0], "V");
                                code.set(index, new MethodStmtNode(statement.op, invocation.args, constructor));
                                count++;
                            }
                        }
                    }
                    allocation = null;
                }
            }
        }
        return count;
    }

    private static boolean canRestoreConstructor(String name, Map<String, DexClassNode> types,
            Set<String> restored, Set<String> visiting) {
        if (name.equals("Ljava/lang/Object;") || restored.contains(name)) return true;
        if (!visiting.add(name)) return false;
        DexClassNode type = types.get(name);
        if (type == null || (type.methods != null && type.methods.stream().anyMatch(candidate ->
                candidate.method.getName().equals("<init>") && candidate.method.getParameterTypes().length == 0))) return false;
        return canRestoreConstructor(type.superClass, types, restored, visiting);
    }

    private static void restoreConstructor(String name, Map<String, DexClassNode> types, Set<String> restored) {
        if (name.equals("Ljava/lang/Object;") || restored.contains(name)) return;
        DexClassNode type = types.get(name);
        restoreConstructor(type.superClass, types, restored);
        Method constructor = new Method(type.className, "<init>", new String[0], "V");
        DexMethodNode synthetic = new DexMethodNode(0x0001, constructor);
        synthetic.visitCode().visitRegister(1);
        synthetic.codeNode.visitMethodStmt(Op.INVOKE_DIRECT, new int[]{0},
            new Method(type.superClass, "<init>", new String[0], "V"));
        synthetic.codeNode.visitStmt0R(Op.RETURN_VOID);
        if (type.methods == null) type.methods = new ArrayList<>();
        type.methods.add(synthetic);
        restored.add(name);
    }
}

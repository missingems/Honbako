package com.missingems.honbako.runtime;

/** A first-party JNI smoke test; this does not claim extension compatibility. */
public final class RuntimeProbe {
    private RuntimeProbe() {}

    public static String run() throws Exception {
        Class<?> type = Class.forName("java.lang.String");
        Object reflected = type.getConstructor(String.class).newInstance("Honbako");
        if (!"Honbako".equals(reflected)) throw new AssertionError("Reflection failed");
        java.util.concurrent.CompletableFuture<Integer> task =
            java.util.concurrent.CompletableFuture.supplyAsync(() -> 17 + 25);
        if (task.get() != 42) throw new AssertionError("Java worker failed");
        return "Java " + System.getProperty("java.version") + "\n"
            + System.getProperty("java.vm.name") + "\n"
            + System.getProperty("java.vm.info") + "\n"
            + "Class Loading: Passed\nReflection: Passed\nJava Worker: Passed";
    }
}

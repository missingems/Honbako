package android.os;

import java.util.concurrent.*;

/** Host-only callback dispatch. A production iOS adapter must use its UI dispatcher. */
public final class Handler {
    private static final ScheduledExecutorService CALLBACKS = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread thread = new Thread(r, "HonbakoProbeCallbacks"); thread.setDaemon(true); return thread;
    });
    public Handler() {}
    public Handler(Looper looper) {}
    public boolean post(Runnable action) { CALLBACKS.execute(action); return true; }
    public boolean postDelayed(Runnable action, long milliseconds) { CALLBACKS.schedule(action, milliseconds, TimeUnit.MILLISECONDS); return true; }
    public Looper getLooper() { return Looper.getMainLooper(); }
}

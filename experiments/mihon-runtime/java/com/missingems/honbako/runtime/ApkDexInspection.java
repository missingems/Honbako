package com.missingems.honbako.runtime;

import com.googlecode.d2j.node.*;
import com.googlecode.d2j.node.insn.*;
import com.googlecode.d2j.reader.MultiDexFileReader;
import java.nio.file.*;

/** Read original DEX nodes before translation; does not modify an extension. */
public final class ApkDexInspection {
    public static void main(String[] args) throws Exception {
        DexFileNode file = new DexFileNode();
        MultiDexFileReader.open(Files.readAllBytes(Paths.get(args[0]))).accept(file);
        for (DexClassNode type : file.clzs) {
            if (args.length > 1 && java.util.Arrays.asList(args).subList(1, args.length).contains(type.className)) {
                System.out.println("ORIGINAL DEX CLASS " + type.className + " extends " + type.superClass);
                if (type.methods == null) continue;
                for (DexMethodNode method : type.methods) {
                    if (!method.method.getName().equals("<init>") && !method.method.getName().equals("<clinit>")) continue;
                    System.out.println("METHOD " + method.method);
                    if (method.codeNode == null) continue;
                    int index = 0;
                    for (DexStmtNode statement : method.codeNode.stmts) {
                        String detail = statement instanceof TypeStmtNode ? ((TypeStmtNode) statement).type + " r" + ((TypeStmtNode) statement).a
                            : statement instanceof MethodStmtNode ? ((MethodStmtNode) statement).method + " " + java.util.Arrays.toString(((MethodStmtNode) statement).args)
                            : statement instanceof ConstStmtNode ? String.valueOf(((ConstStmtNode) statement).value)
                            : statement.getClass().getSimpleName();
                        System.out.println(index++ + " " + statement.op + " " + detail);
                    }
                }
                continue;
            }
            if (args.length > 1) continue;
            if (!type.className.endsWith("/komga/Komga;")) continue;
            for (DexMethodNode method : type.methods) {
                if (method.codeNode == null) continue;
                var statements = method.codeNode.stmts;
                for (int index = 0; index < statements.size(); index++) {
                    DexStmtNode item = statements.get(index);
                    if (!(item instanceof MethodStmtNode) || !((MethodStmtNode) item).method.getName().equals("addNetworkInterceptor")) continue;
                    System.out.println("ORIGINAL DEX METHOD: " + method.method);
                    for (int around = Math.max(0, index - 8); around <= index; around++) {
                        DexStmtNode statement = statements.get(around);
                        String detail = statement instanceof TypeStmtNode ? ((TypeStmtNode) statement).type
                            : statement instanceof MethodStmtNode ? ((MethodStmtNode) statement).method.toString() : statement.getClass().getSimpleName();
                        System.out.println(around + " " + statement.op + " " + detail);
                    }
                }
            }
        }
    }
}

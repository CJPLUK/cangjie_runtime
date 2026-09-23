/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
 * This source file is part of the Cangjie project, licensed under Apache-2.0
 * with Runtime Library Exception.
 *
 * See https://cangjie-lang.cn/pages/LICENSE for license information.
 */

package std.core

public enum Extern<T> where T <: ForeignRuntime<T> {
    | ExternPayload(Any)
    | ExternMemberAccess(Extern<T>, String)
    | ExternIndexedAccess(Extern<T>, Any)
    | ExternMemberUpdate(Extern<T>, String, Any)
    | ExternIndexedUpdate(Extern<T>, Any, Any)
    | ExternFunctionCall(Extern<T>, Array<Any>)
    | ExternCompoundAssignment(Extern<T>, String, Any)
    | ...

    public static func evalDerived(e: Extern<T>): Extern<T> {
        match (e) {
            case _ => throw ExternUnsupportedOperation()
        }
    }
}

public interface ForeignRuntime<T> where T <: ForeignRuntime<T> {
    static func fromExtern<R>(e: Extern<T>): R
    static func toExtern<R>(v: R): Extern<T>
    static func eval(t: Extern<T>): Extern<T>
}

public class ExternMemberAccessException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternMemberAccessException" }
}

public class ExternFunctionAccessException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternFunctionAccessException" }
}

public class ExternFunctionCallException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternFunctionCallException" }
}

public class ExternIndexedAccessException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternIndexedAccessException" }
}

public class ExternCompoundAssignmentException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternCompoundAssignmentException" }
}

public class ExternConversionException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternConversionException" }
}

public class ForeignRuntimeException <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ForeignRuntimeException" }
}

public class ExternUnsupportedOperation <: Exception {
    public init() { super() }
    public init(message: String) { super(message) }
    protected override func getClassName(): String { "ExternUnsupportedOperation" }
}

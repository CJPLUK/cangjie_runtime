/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2026. All rights reserved.
 * This source file is part of the Cangjie project, licensed under Apache-2.0
 * with Runtime Library Exception.
 *
 * See https://cangjie-lang.cn/pages/LICENSE for license information.
 */

macro package std.concurrent.tasksmacro

import std.ast.*
import std.collection.*

class TokensBuilder {
    TokensBuilder(let data: ArrayList<Tokens>) {}
    init() { data = ArrayList() }

    func append(tokens: TokensBuilder): TokensBuilder {
        data.add(all: tokens.data)
        return this
    }

    func append(kind: TokenKind): TokensBuilder {
        data.add(Tokens(Token(kind)))
        return this
    }

    func append<TT>(tokens: TT): TokensBuilder where TT <: ToTokens {
        match (tokens) {
            case tb: TokensBuilder => return append(tb)
            case _ => ()
        }

        data.add(tokens.toTokens())
        return this
    }

    public func toTokens(): Tokens {
        let tokens = ArrayList<Token>()
        for (part in data) {
            for (token in part) {
                tokens.add(token)
            }
        }
        Tokens(tokens)
    }
}

func identifier(name: String): Token {
    Token(TokenKind.IDENTIFIER, name)
}

func identifierTokens(name: String): Tokens {
    Tokens(identifier(name))
}

func commaSeparated<T>(items: Iterable<T>): Tokens where T <: ToTokens {
    let builder = TokensBuilder()
    let it = items.iterator()
    match (it.next()) {
        case Some(first) => builder.append(first)
        case None => return builder.toTokens()
    }
    for (item in it) {
        builder.append(TokenKind.COMMA).append(item)
    }
    builder.toTokens()
}

func repeated(n: Int64, build: (Int64) -> Tokens): ArrayList<Tokens> {
    let parts = ArrayList<Tokens>()
    for (i in 1..(n + 1)) {
        parts.add(build(i))
    }
    parts
}

func typeParameters(n: Int64): Tokens {
    let params = repeated(n, { i => identifierTokens("T${i}") })
    params.add(identifierTokens("S"))
    commaSeparated(params)
}

func tupleTypes(n: Int64): Tokens {
    let types = repeated(n, { i => identifierTokens("T${i}") })
    quote(($(commaSeparated(types))))
}

func taskFields(n: Int64): Tokens {
    let values = repeated(n, { i => quote(this.$(identifier("t${i}"))) })
    quote(($(commaSeparated(values))))
}

func constructorParameters(n: Int64): Tokens {
    commaSeparated(repeated(n, {
        i => quote($(identifier("t${i}")): Task<$(identifier("T${i}")), S>)
    }))
}

func taskFunctionParameters(n: Int64): Tokens {
    commaSeparated(repeated(n, {
        i => quote($(identifier("task${i}")): Task<$(identifier("T${i}")), S>)
    }))
}

func taskConstructorArguments(n: Int64): Tokens {
    commaSeparated(repeated(n, { i => identifierTokens("task${i}") }))
}

func parseUnsignedInteger(value: String): Int64 {
    var parsed = 0
    for (digit in value.runes()) {
        if (!digit.isAsciiNumber()) {
            throw Exception("Expected an integer literal.")
        }
        parsed = parsed * 10 + Int64(UInt32(digit) - UInt32(r'0'))
    }
    parsed
}

func parseArity(attr: Tokens): Int64 {
    if (attr.size != 1 || attr.get(0).kind != TokenKind.INTEGER_LITERAL) {
        throw Exception("@GenerateTasks[n] requires a single integer literal n > 1")
    }
    let n = parseUnsignedInteger(attr.get(0).value)
    if (n <= 1) {
        throw Exception("@GenerateTasks[n] requires n > 1")
    }
    n
}

func appendTasksClass(builder: TokensBuilder, n: Int64): Unit {
    let className = identifier("Tasks${n}")
    let generics = typeParameters(n)
    let tupleType = tupleTypes(n)
    builder.append(quote(
internal class $(className)<$(generics)> <: Task<$(tupleType), S> & Takes<Unit> where S <: Spawner {
    let tasksLeft = AtomicUInt32($(n))
    let failed = AtomicBool(false)
))
    for (i in 1..(n + 1)) {
        builder.append(quote(
    var $(identifier("t${i}")) = unsafe { zeroValue<$(identifier("T${i}"))>() }
))
    }
    builder.append(quote(

    $(className)($(constructorParameters(n)), spawner: S) {
        super(spawner)
        initNativeResources()
))
    for (i in 1..(n + 1)) {
        builder.append(quote(
        $(identifier("t${i}")).addFastContinuation($(identifier("Tasks${n}_${i}"))(this))
))
    }
    builder.append(quote(
    }

    public func next(_: Unit): ?TaskChainLink {
        let outcome = $(taskFields(n))
        this.complete(Success(outcome))
        if (Thread.currentThread.hasPendingCancellation) {
            this.propagateFailureToContinuations(Excepted(TaskCancelledException()))
            return None
        }
        nextRunnableContinuation(outcome)
    }

    public func propagateFailure(fail: Failure): Unit {
        if (!this.failed.swap(true)) {
            this.complete(Fail(fail))
            this.propagateFailureToContinuations(fail)
        }
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        if (!this.failed.swap(true)) {
            this.complete(Fail(fail))
            this.propagateFailureToContinuationsInline(fail)
        } else {
            None
        }
    }
}

))
}

func appendContinuationClass(builder: TokensBuilder, n: Int64, i: Int64): Unit {
    let className = identifier("Tasks${n}_${i}")
    let wrappedName = identifier("Tasks${n}")
    let generics = typeParameters(n)
    let typeName = identifier("T${i}")
    let fieldName = identifier("t${i}")
    builder.append(quote(
internal class $(className)<$(generics)> <: Takes<$(typeName)> where S <: Spawner {
    $(className)(let wrapped: $(wrappedName)<$(generics)>) {}

    public func next(t: $(typeName)): ?TaskChainLink {
        this.wrapped.$(fieldName) = t
        if (this.wrapped.tasksLeft.fetchSub(1) == 1) {
            RunnableContinuation(this.wrapped, ())
        } else {
            None
        }
    }

    public func propagateFailure(fail: Failure): Unit {
        this.wrapped.propagateFailure(fail)
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        this.wrapped.propagateFailureInline(fail)
    }
}

))
}

func appendTasksFunction(builder: TokensBuilder, n: Int64): Unit {
    let className = identifier("Tasks${n}")
    let generics = typeParameters(n)
    let tupleType = tupleTypes(n)
    builder.append(quote(
public func tasks<$(generics)>($(taskFunctionParameters(n))): Task<$(tupleType), S> where S <: Spawner {
    $(className)($(taskConstructorArguments(n)), task1.spawner)
}
))
}

/*
 * Usage:
 *
 * @GenerateTasks[4]
 * struct _GenerateTasks4 {}
 */
public macro GenerateTasks(attr: Tokens, _: Tokens): Tokens {
    let n = parseArity(attr)
    let builder = TokensBuilder()
    appendTasksClass(builder, n)
    for (i in 1..(n + 1)) {
        appendContinuationClass(builder, n, i)
    }
    appendTasksFunction(builder, n)
    builder.toTokens()
}

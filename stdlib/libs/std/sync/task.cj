/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
 * This source file is part of the Cangjie project, licensed under Apache-2.0
 * with Runtime Library Exception.
 *
 * See https://cangjie-lang.cn/pages/LICENSE for license information.
 */

package std.core

@Intrinsic
func futureInit<T, I>(future: Future<T, I>): Unit

@Intrinsic
func futureIsComplete<T, I>(future: Future<T, I>): Bool

@Intrinsic
func futureWait<T, I>(future: Future<T, I>, timeout: Int64): Unit

@Intrinsic
func futureNotifyAll<T, I>(future: Future<T, I>): Unit

@Intrinsic
func futureLockContinuationsOrAlreadyComplete<T, I>(future: Future<T, I>): Bool

@Intrinsic
func futureUnlockContinuations<T, I>(future: Future<T, I>): Unit

@Intrinsic
func futureNotifyEndThread<T, I>(future: Future<T, I>): Unit

@FastNative
foreign func CJ_CORE_PrintOomHint(): Unit

let INT64_MAX: Int64 = 0x7fff_ffff_ffff_ffffi64

internal enum TaskState<T> {
    | Pending
    // Completed is a terminal state,
    // should not be mutated after being set to this
    | Completed(TaskOutcome<T>)
}

internal enum TaskOutcome<T> {
    | Success(T)
    | Fail(Failure)

    internal func unwrapOrThrow(): T {
        match (this) {
            case Success(output) => return output
            case Fail(Excepted(exc)) => throw exc
            case Fail(Errored(err)) => throw err
        }
    }
}

protected enum Failure {
    | Errored(Error)
    | Excepted(Exception)
}

protected abstract class Takes<I> {
    // Run Continuation body inline, and return a
    // handle which allows running the first dependent
    // continuation which its output
    // (and launches the others automatically)
    protected func next(arg: I): ?ContinuousInlineExecution
    // Set the state of all dependents (recursively) to the failure
    // and notify completion.
    protected func propagateFailure(fail: Failure): Unit

    protected func execute(arg: I): Unit {
        RunnableContinuation(this, arg).executeContinuously()
    }
}

// Abstract class with no generic parameters necessary to perform
// the runtime polymorphism in `launch` to loop through successive
// continuations regardless of their input/output types.
protected abstract class ContinuousInlineExecution {
    // Run the body closure in a new thread,
    // which successively runs the first dependent
    // continuation (in the same thread), and `launch`es
    // the others.
    // The `launch`ed thread terminates when it completes
    // executing the closure of a continuation which has no
    // dependents.
    protected func executeContinuously(): Unit {
        // We want this to be written as a loop instead of
        // the more obvious recursive implementation to scale better
        var taskIter: ContinuousInlineExecution = this
        while (let Some(next) <- taskIter.next()) {
            taskIter = next
        }
    }

    protected func next(): ?ContinuousInlineExecution
}

// Using a continuation on its own requires the knowledge of the type of
// value needed to execute it; however when paired with an input value,
// we can execute it, and then at the end pair the output with its first
// dependent continuation to produce another element of this abstract class
// above.
protected class RunnableContinuation<I> <: ContinuousInlineExecution {
    RunnableContinuation(let cont: Takes<I>, let arg: I) {}

    protected func next(): ?ContinuousInlineExecution {
        cont.next(arg)
    }
}

public class Future<T, I> <: Takes<I> {
    // `_thread` must be the first field,
    // it will be accessed when spawning a runtime cj thread.
    private var state: TaskState<T> = Pending
    private let bindThread: Bool
    private var executeFn: (I) -> T
    private var nextContinuations: Array<Takes<T>> = Array<Takes<T>>()

    private init(fn: () -> T) {
        this.bindThread = true
        this.executeFn = { _ => fn() }
        unsafe { futureInit(this) }
    }

    init(fn: (I) -> T) {
        this.bindThread = false
        this.executeFn = fn
        unsafe { futureInit(this) }
    }

    /**
     * Blocking the current thread,
     * waiting for the result of the thread corresponding to this Future object.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func get(): T {
        unsafe { futureWait(this, Int64.Max) }
        match (state) {
            case Pending => get()
            case Completed(outcome) => outcome.unwrapOrThrow()
        }
    }

    /**
     * Non-blocking method that immediately returns None if thread has not finished execution.
     * Returns the computed result otherwise.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func tryGet(): Option<T> {
        let isComplete = unsafe { futureIsComplete(this) }
        if (!isComplete) {
            return Option<T>.None
        }
        match (state) {
            case Pending => Option<T>.None
            case Completed(outcome) => outcome.unwrapOrThrow()
        }
    }

    /**
     * Blocking the current thread,
     * waiting for the result of the thread corresponding to this Future object.
     * If the corresponding thread has not completed execution within `ns` nanoseconds,
     * the method will return `Option<T>.None`.
     * If `ns <= 0`, same as `get()`.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func get(timeout: Duration): T {
        if (timeout <= Duration.Zero) {
            return get()
        }
        // Wait for `ns` nanoseconds
        unsafe { futureWait(this, timeout.toNanoseconds()) }
        // Check whether the future is complete
        let isCompleteAfterWait = unsafe { futureIsComplete(this) }
        if (!isCompleteAfterWait) {
            throw TimeoutException()
        }
        match (state) {
            case Pending => return get() // maybe throw
            case Completed(outcome) => return outcome.unwrapOrThrow()
        }
    }

    protected func next(input: I): ?ContinuousInlineExecution {
        let outcome: TaskOutcome<T> = try {
            Success(executeFn(input))
        } catch (ex: Exception) {
            handleException(ex)
            Fail(Excepted(ex))
        } catch (er: OutOfMemoryError) {
            unsafe { CJ_CORE_PrintOomHint() }
            handleError(er)
            Fail(Errored(er))
        } catch (er: Error) {
            er.printStackTrace()
            handleError(er)
            Fail(Errored(er))
        }
        state = Completed(outcome)
        unsafe { futureNotifyAll(this) } // wake up the `.get()` threads
        // Now this only thread which can (should) access nextContinuations
        match (outcome) {
            case Success(output) =>
                if (nextContinuations.size > 0) {
                    let out = RunnableContinuation(nextContinuations[0], output)
                    for (i in 1..nextContinuations.size) {
                        spawn {
                            nextContinuations[i].execute(output)
                        }
                    }
                    return out
                }
            case Fail(cause) => propagateFailureInner(cause)
        }
        return None
    }

    // assumes NOT already notified
    protected func propagateFailure(fail: Failure): Unit {
        state = Completed(Fail(fail))
        unsafe { futureNotifyAll(this) } // wake up the `.get()` threads
        propagateFailureInner(fail)
    }

    // assumes already notified
    private func propagateFailureInner(fail: Failure): Unit {
        for (i in 0..nextContinuations.size) {
            nextContinuations[i].propagateFailure(fail)
        }
    }

    internal func appendContinuation(next: Takes<T>): Unit {
        nextContinuations = nextContinuations.concat(Array<Takes<T>>(1, {_ => next}))
    }

    internal func getCompletedOutput(): T {
        match (state) {
            case Completed(outcome) => outcome.unwrapOrThrow()
            case Pending => throw IllegalStateException("Future should be completed")
        }
    }

    internal func executeInline(input: I): Unit {
        RunnableContinuation(this, input).executeContinuously()
        unsafe { futureNotifyEndThread(this) }
        return
    }

    // internal func requestCancellation(): Unit {
        // this._thread.setCancellationRequest()
    // }

    // internal func getThread(): Thread {
        // _thread
    // }

    internal func executeAsSpawnRoot(input: I): Unit {
        if (bindThread) {
            this._thread.waitForCJThreadHandle()
            setThreadObject(this._thread)
        }

        executeInline(input)

        if (bindThread) {
            this._thread.clearRuntimeCJThreadHandle()
        }
    }
}

extend<T, I> Future<T, I> {
    public func then<U>(fn: (T) -> U): Future<U, T> {
        let next = Future<U, T>(fn)
        let taken: Takes<T> = next
        if (unsafe { futureLockContinuationsOrAlreadyComplete(this) }) {
            this.appendContinuation(taken)
            unsafe { futureUnlockContinuations(this) }
        } else {
            let output = this.getCompletedOutput()
            spawn {
                next.executeInline(output)
            }
        }
        return next
    }
}

extend<T> Future<T, Unit> {
    public prop thread: Thread {
        get() {
            this.getThread()
        }
    }

    /**
     * Mark the current future as cancelled.
     * Send a termination request to its executing thread.
     */
    public func cancel(): Unit {
        this.requestCancellation()
    }

    /**
     * Execute the task (thread) and set its result.
     * This method is the entry function of a new thread with a future,
     * and it will be used by CodeGen directly and passed to Cangjie runtime.
     ** BE AWARE OF: **
     * This method is tied to the runtime implementation details,
     * and if you want to make any changes, you should consider
     * whether you need to update the runtime implementation as well.
     */
    func execute(): Unit {
        this.executeAsSpawnRoot(unsafe { zeroValue<Unit>() })
    }

    // ** BE AWARE OF: **
    // This method is tied to the runtime implementation details,
    // and if you want to make any changes, you should consider
    // whether you need to update the runtime implementation as well..
    static func executeClosure(fn: () -> T): Unit {
        try {
            fn()
        } catch (ex: Exception) {
            handleException(ex)
        } catch (_: OutOfMemoryError) {
            eprintln("An exception has occurred:")
            eprintln("    Out of memory")
        } catch (er: Error) {
            er.printStackTrace()
        }
        return
    }

}

/**
 * The optional argument type of the `spawn` expression.
 * Specific derived types of `ThreadContext` could affect the behavior of the thread at runtime.
 * Only for `MainThreadContext` by now.
 */
public interface ThreadContext {
    func end(): Unit
    func hasEnded(): Bool
}

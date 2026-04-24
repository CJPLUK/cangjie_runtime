/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
 * This source file is part of the Cangjie project, licensed under Apache-2.0
 * with Runtime Library Exception.
 *
 * See https://cangjie-lang.cn/pages/LICENSE for license information.
 */

package std.concurrent

@Intrinsic
func taskInit<T>(task: Task<T>): Unit

@Intrinsic
func taskIsComplete<T>(task: Task<T>): Bool

@Intrinsic
func taskContinuationsAreLocked<T>(task: Task<T>): Bool

@Intrinsic
func taskWait<T>(task: Task<T>, timeout: Int64): Unit

@Intrinsic
func taskNotifyAll<T>(task: Task<T>): Unit

@Intrinsic
func taskLockContinuationsOrAlreadyComplete<T>(task: Task<T>): Int64

@Intrinsic
func taskUnlockContinuations<T>(task: Task<T>): Unit

@Intrinsic
func taskNotifyEndThread<T>(task: Task<T>): Unit

@FastNative
foreign func CJ_CORE_PrintOomHint(): Unit

internal class NextContinuations<T> {
    public var elements: Array<Takes<T>> = Array<Takes<T>>(4, repeat: DummyContinuation())
    public var size = 0

    public func add(elem: Takes<T>): Unit {
        if (size >= elements.size) {
            elements = elements.concat(Array<Takes<T>>(elements.size, repeat: DummyContinuation<T>()))
        }
        elements[size] = elem
        size++
    }
}

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

internal enum Failure {
    | Errored(Error)
    | Excepted(Exception)
}

internal interface FailurePropagator {
    // Set the state of all dependents (recursively) to the failure
    // and notify completion.
    func propagateFailure(fail: Failure): Unit
}

internal interface Takes<I> <: FailurePropagator {
    // Run Continuation body inline, and return a
    // handle which allows running the first dependent
    // continuation which its output
    func next(arg: I): ?ContinuousInlineExecution

    func execute(arg: I): Unit {
        RunnableContinuation(this, arg).executeContinuously()
    }
}

internal class DummyContinuation<T> <: Takes<T> {
    public func next(arg: T): ?ContinuousInlineExecution { None }
    public func propagateFailure(fail: Failure): Unit {}
}

// Abstract class with no generic parameters necessary to perform
// the runtime polymorphism in `launch` to loop through successive
// continuations regardless of their input/output types.
internal abstract class ContinuousInlineExecution {
    // Run the body closure in a new thread,
    // which successively runs the first dependent
    // continuation (in the same thread), and `launch`es
    // the others.
    // The `launch`ed thread terminates when it completes
    // executing the closure of a continuation which has no
    // dependents.
    public func executeContinuously(): Unit {
        // We want this to be written as a loop instead of
        // the more obvious recursive implementation to scale better
        var taskIter: ContinuousInlineExecution = this
        while (let Some(next) <- taskIter.next()) {
            taskIter = next
        }
    }

    public func next(): ?ContinuousInlineExecution
}

// Using a continuation on its own requires the knowledge of the type of
// value needed to execute it; however when paired with an input value,
// we can execute it, and then at the end pair the output with its first
// dependent continuation to produce another element of this abstract class
// above.
internal class RunnableContinuation<I> <: ContinuousInlineExecution {
    RunnableContinuation(let cont: Takes<I>, let arg: I) {}

    public func next(): ?ContinuousInlineExecution {
        cont.next(arg)
    }
}

public interface Getable<T> {
    func get(): T
    func tryGet(): ?T
    func get(timeout: Duration): T
}

public interface Chainable<T> {
    func then<U>(f: (T) -> U): Task<U>
    func recover<E>(h: (E) -> T): Task<T> where E <: Exception
}

abstract sealed class Task<T> <: Getable<T> {
    internal var state: TaskState<T> = Pending
    internal var nextContinuations = NextContinuations<T>()
    public var nativeResources = VArray<Int64, $15>(repeat: 0)


    protected func initNativeResources() {
        unsafe { taskInit(this) }
    }
    /**
     * Blocking the current thread,
     * waiting for the result of the thread corresponding to this InternalTask object.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func get(): T {
        if ( unsafe { taskIsComplete(this) } ) {
            match (state) {
                case Pending => throw IllegalStateException("Task must be complete at this point")
                case Completed(outcome) => outcome.unwrapOrThrow()
            }
        }
        unsafe { taskWait(this, Int64.Max) }
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
        let isComplete = unsafe { taskIsComplete(this) }
        if (!isComplete) {
            return None
        }
        match (state) {
            case Pending => None
            case Completed(outcome) => outcome.unwrapOrThrow()
        }
    }

    /**
     * Blocking the current thread,
     * waiting for the result of the thread corresponding to this Task object.
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
        unsafe { taskWait(this, timeout.toNanoseconds()) }
        // Check whether the task is complete
        let isCompleteAfterWait = unsafe { taskIsComplete(this) }
        if (!isCompleteAfterWait) {
            throw TimeoutException()
        }
        match (state) {
            case Pending => return get()
            case Completed(outcome) => return outcome.unwrapOrThrow()
        }
    }
}

internal class InternalTask<I, T> <: Task<T> & Takes<I> {
    internal var executeFn: (I) -> T

    InternalTask(fn: (I) -> T) {
        this.executeFn = fn
        initNativeResources()
    }

    public func next(input: I): ?ContinuousInlineExecution {
        let outcome: TaskOutcome<T> = try {
            Success(executeFn(input))
        } catch (ex: Exception) {
            Fail(Excepted(ex))
        } catch (er: OutOfMemoryError) {
            unsafe { CJ_CORE_PrintOomHint() }
            Fail(Errored(er))
        } catch (er: Error) {
            er.printStackTrace()
            Fail(Errored(er))
        }
        state = Completed(outcome)
        unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
        while (unsafe { taskContinuationsAreLocked(this) }) {
            sleep(Duration.Zero)
        }
        // Now this only thread which can (should) access nextContinuations
        match (outcome) {
            case Success(output) =>
                if (nextContinuations.size > 0) {
                    let out = RunnableContinuation<T>(nextContinuations.elements[0], output)
                    for (i in 1..nextContinuations.size) {
                        spawn {
                            RunnableContinuation<T>(nextContinuations.elements[i], output).executeContinuously()
                        }
                    }
                    return out
                }
            case Fail(cause) => propagateFailureInner(cause)
        }
        return None
    }

    // assumes NOT already notified
    public func propagateFailure(fail: Failure): Unit {
        state = Completed(Fail(fail))
        unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
        propagateFailureInner(fail)
    }

    // assumes already notified
    private func propagateFailureInner(fail: Failure): Unit {
        for (i in 0..nextContinuations.size) {
            nextContinuations.elements[i].propagateFailure(fail)
        }
    }
}

internal class InternalCatch<E, T> <: Task<T> & Takes<T> & Takes<E> where E <: Exception{
    internal var handlerFn: (E) -> T

    InternalCatch(fn: (E) -> T) {
        this.handlerFn = fn
        initNativeResources()
    }

    public func next(input: T): ?ContinuousInlineExecution {
        let output = input
        state = Completed(Success(output))
        unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
        while (unsafe { taskContinuationsAreLocked(this) }) {
            sleep(Duration.Zero)
        }
        // Now this only thread which can (should) access nextContinuations
        if (nextContinuations.size > 0) {
            let out = RunnableContinuation<T>(nextContinuations.elements[0], output)
            for (i in 1..nextContinuations.size) {
                spawn {
                    RunnableContinuation<T>(nextContinuations.elements[i], output).executeContinuously()
                }
            }
            return out
        }
        return None
    }

    public func next(exc: E): ?ContinuousInlineExecution {
        let outcome: TaskOutcome<T> = try {
            Success(handlerFn(exc))
        } catch (ex: Exception) {
            Fail(Excepted(ex))
        } catch (er: OutOfMemoryError) {
            unsafe { CJ_CORE_PrintOomHint() }
            Fail(Errored(er))
        } catch (er: Error) {
            er.printStackTrace()
            Fail(Errored(er))
        }
        state = Completed(outcome)
        unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
        while (unsafe { taskContinuationsAreLocked(this) }) {
            sleep(Duration.Zero)
        }
        // Now this only thread which can (should) access nextContinuations
        match (outcome) {
            case Success(output) =>
                if (nextContinuations.size > 0) {
                    let out = RunnableContinuation<T>(nextContinuations.elements[0], output)
                    for (i in 1..nextContinuations.size) {
                        spawn {
                            RunnableContinuation<T>(nextContinuations.elements[i], output).executeContinuously()
                        }
                    }
                    return out
                }
            case Fail(cause) => propagateFailureInner(cause)
        }
        return None
    }

    // assumes NOT already notified
    public func propagateFailure(fail: Failure): Unit {
        if ((let Excepted(exc) <- fail) && (let Some(e) <- (exc as E))) {
            // The failure was an exception that this handler catches
            spawn {
                RunnableContinuation<E>(this, e).executeContinuously()
            }
        } else {
            state = Completed(Fail(fail))
            unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
            propagateFailureInner(fail)
        }
    }

    // assumes already notified
    private func propagateFailureInner(fail: Failure): Unit {
        for (i in 0..nextContinuations.size) {
            nextContinuations.elements[i].propagateFailure(fail)
        }
    }
}

extend<T> Task<T> <: Chainable<T> {
    public func then<U>(fn: (T) -> U): Task<U> {
        let next = InternalTask<T, U>(fn)
        let taken: Takes<T> = next
        while (true) {
            let ret = unsafe { taskLockContinuationsOrAlreadyComplete(this) }
            if (ret == 1) {
                this.nextContinuations.add(taken)
                unsafe { taskUnlockContinuations(this) }
                break
            }
            if (ret == 0) {
                let output = match (this.state) {
                    case Completed(outcome) => outcome.unwrapOrThrow()
                    case Pending => throw IllegalStateException("Task is not complete")
                }
                spawn {
                    RunnableContinuation(next, output).executeContinuously()
                }
                break
            }
            // otherwise it's been locked by another cjthread
            sleep(Duration.Zero)
        }
        return next
    }

    public func recover<E>(h: (E) -> T): Task<T> where E <: Exception {
        let next = InternalCatch<E, T>(h)
        let taken: Takes<T> = next
        while (true) {
            let ret = unsafe { taskLockContinuationsOrAlreadyComplete(this) }
            if (ret == 1) {
                this.nextContinuations.add(taken)
                unsafe { taskUnlockContinuations(this) }
                break
            }
            if (ret == 0) {
                let output = match (this.state) {
                    case Completed(outcome) => outcome.unwrapOrThrow()
                    case Pending => throw IllegalStateException("Task is not complete")
                }
                spawn {
                    RunnableContinuation(next, output).executeContinuously()
                }
                break
            }
            // otherwise it's been locked by another cjthread
            sleep(Duration.Zero)
        }
        return next
    }
}

public func task<T>(f: () -> T): Task<T> {
    let output = InternalTask<Unit, T> { _ => f() }
    spawn {
        RunnableContinuation<Unit>(output, ()).executeContinuously()
    }
    output
}

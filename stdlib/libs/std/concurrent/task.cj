/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
 * This source file is part of the Cangjie project, licensed under Apache-2.0
 * with Runtime Library Exception.
 *
 * See https://cangjie-lang.cn/pages/LICENSE for license information.
 */

package std.concurrent
import std.core.zeroValue

@Intrinsic
func taskInit<T, S>(task: Task<T, S>): Unit where S <: Spawner

@Intrinsic
func taskIsComplete<T, S>(task: Task<T, S>): Bool where S <: Spawner

@Intrinsic
func taskContinuationsAreLocked<T, S>(task: Task<T, S>): Bool where S <: Spawner

@Intrinsic
func taskWait<T, S>(task: Task<T, S>, timeout: Int64): Unit where S <: Spawner

@Intrinsic
func taskNotifyAll<T, S>(task: Task<T, S>): Unit where S <: Spawner

@Intrinsic
func taskLockContinuationsOrAlreadyComplete<T, S>(task: Task<T, S>): Int64 where S <: Spawner

@Intrinsic
func taskUnlockContinuations<T, S>(task: Task<T, S>): Unit where S <: Spawner

@Intrinsic
func taskNotifyEndThread<T, S>(task: Task<T, S>): Unit where S <: Spawner

@FastNative
foreign func CJ_CORE_PrintOomHint(): Unit

internal class NextContinuations<T> {
    public var elements = Array<Takes<T>>(4, repeat: unsafe { zeroValue<Takes<T>>() })
    public var size = 0

    public func add(elem: Takes<T>): Unit {
        if (size >= elements.size) {
            elements = elements.concat(
                Array<Takes<T>>(
                    elements.size,
                    repeat: unsafe { zeroValue<Takes<T>>() }
                )
            )
        }
        elements[size] = elem
        size++
    }
}

// Completed is a terminal state,
// should not be mutated after being set to this
internal enum TaskState<T> {
    Pending | Completed(TaskOutcome<T>)
}

internal enum TaskOutcome<T> {
    Success(T) | Fail(Failure)

    internal func unwrapOrThrow(): T {
        match (this) {
            case Success(output) => return output
            case Fail(Excepted(exc)) => throw exc
            case Fail(Errored(err)) => throw err
        }
    }

    internal static func captureOutcome<I>(fn: (I) -> T, input: I): TaskOutcome<T> {
        try {
            Success(fn(input))
        } catch (ex: Exception) {
            Fail(Excepted(ex))
        } catch (er: OutOfMemoryError) {
            unsafe { CJ_CORE_PrintOomHint() }
            Fail(Errored(er))
        } catch (er: Error) {
            er.printStackTrace()
            Fail(Errored(er))
        }
    }
}

internal enum Failure {
    Errored(Error) | Excepted(Exception)
}

public class TaskCancelledException <: Exception {}

internal interface FailurePropagator {
    // Set the state of all dependents (recursively) to the failure
    // and notify completion.
    func propagateFailure(fail: Failure): Unit
    func propagateFailureInline(fail: Failure): ?TaskChainLink
}

internal interface Takes<I> <: FailurePropagator {
    // Run Continuation body inline, and return a
    // handle which allows running the first dependent
    // continuation which its output
    func next(arg: I): ?TaskChainLink
}

sealed interface Spawner {
    func launch(fn: () -> Unit): Unit
}

public class DefaultSpawner <: Spawner {
    public func launch(fn: () -> Unit): Unit {
        spawn { fn() }
    }
}

// Abstract class with no generic parameters necessary to perform
// the runtime polymorphism in `launch` to loop through successive
// continuations regardless of their input/output types.
internal abstract class TaskChainLink {
    // Run the body closure in a new thread,
    // which successively runs the first dependent
    // continuation (in the same thread), and `launch`es
    // the others.
    // The `launch`ed thread terminates when it completes
    // executing the closure of a continuation which has no
    // dependents.
    public func inlineChainExecution(): Unit {
        // We want this to be written as a loop instead of
        // the more obvious recursive implementation to scale better
        var taskIter: TaskChainLink = this
        while (let Some(next) <- taskIter.next()) {
            taskIter = next
        }
    }

    public func next(): ?TaskChainLink
}

// Using a continuation on its own requires the knowledge of the type of
// value needed to execute it; however when paired with an input value,
// we can execute it, and then at the end pair the output with its first
// dependent continuation to produce another element of this abstract class
// above.
internal class RunnableContinuation<I> <: TaskChainLink {
    RunnableContinuation(let cont: Takes<I>, let arg: I) {}

    public func next(): ?TaskChainLink {
        cont.next(arg)
    }
}

public interface Getable<T> {
    func get(): T
    func tryGet(): ?T
    func get(timeout: Duration): T
}

public interface Chainable<T, S> where S <: Spawner {
    func then<U>(f: (T) -> U): Task<U, S>
    func recover<E>(h: (E) -> T): Task<T, S> where E <: Exception
}

sealed abstract class Task<T, S> <: Getable<T> where S <: Spawner {
    internal var state: TaskState<T> = Pending
    internal var nextContinuations = NextContinuations<T>()
    public var nativeResources = VArray<Int64, $15>(repeat: 0)
    let spawner: S

    Task(s: S) {
        spawner = s
    }

    protected func initNativeResources() {
        unsafe { taskInit(this) }
    }

    internal func complete(outcome: TaskOutcome<T>): Unit {
        this.state = Completed(outcome)
        unsafe { taskNotifyAll(this) } // wake up the `.get()` threads
    }

    internal func completeAndWaitContinuationsUnlocked(outcome: TaskOutcome<T>): Unit {
        this.complete(outcome)
        while (unsafe { taskContinuationsAreLocked(this) }) {
            sleep(Duration.Zero)
        }
    }

    internal func nextRunnableContinuation(output: T): ?TaskChainLink {
        if (this.nextContinuations.size > 0) {
            let out = RunnableContinuation<T>(nextContinuations.elements[0], output)
            for (i in 1..nextContinuations.size) {
                this.spawner.launch(
                    RunnableContinuation<T>(nextContinuations.elements[i], output).inlineChainExecution
                )
            }
            return out
        }
        return None
    }

    internal func nextRunnableContinuation(outcome: TaskOutcome<T>): ?TaskChainLink {
        // Now this only thread which can (should) access nextContinuations
        match (outcome) {
            case Success(output) => this.nextRunnableContinuation(output)
            case Fail(cause) => this.propagateFailureToContinuationsInline(cause)
        }
    }

    // assumes already notified
    internal func propagateFailureToContinuations(fail: Failure): Unit {
        for (i in 0..nextContinuations.size) {
            this.nextContinuations.elements[i].propagateFailure(fail)
        }
    }

    internal func propagateFailureToContinuationsInline(fail: Failure): ?TaskChainLink {
        for (i in 0..nextContinuations.size) {
            let next = this.nextContinuations.elements[i].propagateFailureInline(fail) ?? continue
            for (j in (i+1)..nextContinuations.size) {
                this.nextContinuations.elements[j].propagateFailure(fail)
            }
            return next
        }
        return None
    }

    internal func addContinuation(next: Takes<T>): Unit {
        do {
            let ret = unsafe { taskLockContinuationsOrAlreadyComplete(this) }
            if (ret == 1) {
                this.nextContinuations.add(next)
                unsafe { taskUnlockContinuations(this) }
                return
            }
            if (ret == 0) {
                let output = match (this.state) {
                    case Completed(outcome) => outcome.unwrapOrThrow()
                    case Pending => throw IllegalStateException("Task is not complete")
                }
                this.spawner.launch(RunnableContinuation(next, output).inlineChainExecution)
                return
            }
            // otherwise it's been locked by another cjthread
            sleep(Duration.Zero)
        } while (true)
    }

    /**
     * Blocking the current thread,
     * waiting for the result of the thread corresponding to this InternalTask object.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func get(): T {
        if (unsafe { !taskIsComplete(this) }) {
            unsafe { taskWait(this, Int64.Max) }
        }
        match (this.state) {
            case Pending => throw IllegalStateException("Task must be complete at this point")
            case Completed(outcome) => outcome.unwrapOrThrow()
        }
    }

    /**
     * Non-blocking method that immediately returns None if thread has not finished execution.
     * Returns the computed result otherwise.
     * @throws Exception or Error if an exception occurs in the corresponding thread.
     */
    public func tryGet(): ?T {
        if (unsafe { !taskIsComplete(this) }) {
            return None
        }
        match (state) {
            case Pending => None // Potentially throw exception instead
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
            return this.get()
        }
        // Wait for `ns` nanoseconds
        unsafe { taskWait(this, timeout.toNanoseconds()) }
        // Check whether the task is complete
        if (unsafe { !taskIsComplete(this) }) {
            throw TimeoutException()
        }
        match (state) {
            case Pending => throw IllegalStateException("Task is not complete")
            case Completed(outcome) => return outcome.unwrapOrThrow()
        }
    }
}

internal class InternalTask<I, T, S> <: Task<T, S> & Takes<I> where S <: Spawner {
    InternalTask(spawner: S, internal var executeFn: (I) -> T) {
        super(spawner)
        initNativeResources()
    }

    public func next(input: I): ?TaskChainLink {
        let outcome = TaskOutcome<T>.captureOutcome<I>(executeFn, input)
        completeAndWaitContinuationsUnlocked(outcome)
        if (Thread.currentThread.hasPendingCancellation) {
            this.propagateFailureToContinuations(Excepted(TaskCancelledException()))
            return None
        }
        nextRunnableContinuation(outcome)
    }

    public func propagateFailure(fail: Failure): Unit {
        this.complete(Fail(fail))
        this.propagateFailureToContinuations(fail)
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        this.complete(Fail(fail))
        this.propagateFailureToContinuationsInline(fail)
    }
}

internal class InternalCatch<E, T, S> <: Task<T, S> & Takes<T> & Takes<E> where E <: Exception, S <: Spawner {
    InternalCatch(spawner: S, internal var handlerFn: (E) -> T) {
        super(spawner)
        this.initNativeResources()
    }

    public func next(input: T): ?TaskChainLink {
        this.completeAndWaitContinuationsUnlocked(Success(input))
        this.nextRunnableContinuation(input)
    }

    public func next(exc: E): ?TaskChainLink {
        let outcome = TaskOutcome<T>.captureOutcome<E>(handlerFn, exc)
        this.completeAndWaitContinuationsUnlocked(outcome)
        if (Thread.currentThread.hasPendingCancellation) {
            this.propagateFailureToContinuations(Excepted(TaskCancelledException()))
            return None
        }
        this.nextRunnableContinuation(outcome)
    }

    public func propagateFailure(fail: Failure): Unit {
        if (let Excepted(exc: E) <- fail) {
            this.spawner.launch(RunnableContinuation<E>(this, exc).inlineChainExecution)
        } else {
            this.complete(Fail(fail))
            this.propagateFailureToContinuations(fail)
        }
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        if (let Excepted(exc: E) <- fail) {
            RunnableContinuation<E>(this, exc)
        } else {
            this.complete(Fail(fail))
            this.propagateFailureToContinuationsInline(fail)
        }
    }
}

extend<T, S> Task<T, S> <: Chainable<T, S> where S <: Spawner {
    public func then<U>(fn: (T) -> U): Task<U, S> {
        let next = InternalTask<T, U, S>(this.spawner, fn)
        this.addContinuation(next)
        return next
    }

    public func recover<E>(h: (E) -> T): Task<T, S> where E <: Exception {
        let next = InternalCatch<E, T, S>(this.spawner, h)
        this.addContinuation(next)
        return next
    }
}

public func task<T>(f: () -> T): Task<T, DefaultSpawner> {
    let spawner = DefaultSpawner()
    let output = InternalTask<Unit, T, DefaultSpawner>(spawner) {_ => f()}
    spawner.launch(RunnableContinuation<Unit>(output, ()).inlineChainExecution)
    output
}

public func task<T, S>(spawner: S, f: () -> T): Task<T, S> where S <: Spawner {
    let output = InternalTask<Unit, T, S>(spawner) {_ => f()}
    spawner.launch(RunnableContinuation<Unit>(output, ()).inlineChainExecution)
    output
}
